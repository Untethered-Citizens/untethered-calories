import Foundation
import SwiftData

enum DataStore {
    static let schema = Schema([MealEntry.self, DailySummary.self, Targets.self, UsualMeal.self, TokenUsage.self])

    /// The app's container. `inMemory` is for tests and previews.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

enum DailySummaryStore {
    /// Returns the day's row, creating it if there is none. Never assume it exists,
    /// and never create one without looking first. Pending (unsaved) inserts are
    /// included in the lookup, so this is safe inside a transaction.
    static func getOrCreate(_ date: LocalDate, in context: ModelContext) throws -> DailySummary {
        if let existing = try find(date, in: context) { return existing }
        let row = DailySummary(date: date)
        context.insert(row)
        return row
    }

    static func find(_ date: LocalDate, in context: ModelContext) throws -> DailySummary? {
        let key = date.iso
        var descriptor = FetchDescriptor<DailySummary>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// An entry on its way in, with how its numbers were obtained.
struct PendingEntry: Codable, Sendable {
    var draft: EntryDraft
    var origin: EntryOrigin
}

struct WriteRejected: Error, Equatable {
    /// Issues keyed by the index of the pending entry they belong to.
    let issues: [Int: [IntegrityIssue]]
}

/// The write boundary. A batch is checked in full, then written as one transaction,
/// or not written at all.
enum EntryWriter {
    @discardableResult
    static func commit(_ batch: [PendingEntry], confirmedByUser: Bool,
                       in context: ModelContext, now: Date = Date()) throws -> [MealEntry] {
        var problems: [Int: [IntegrityIssue]] = [:]
        for (index, pending) in batch.enumerated() {
            let found = Integrity.issues(for: pending.draft, origin: pending.origin, confirmedByUser: confirmedByUser)
            if !found.isEmpty { problems[index] = found }
        }
        guard problems.isEmpty else { throw WriteRejected(issues: problems) }

        var written: [MealEntry] = []
        try context.transaction {
            for pending in batch {
                let entry = MealEntry(pending.draft, createdAt: now)
                context.insert(entry)
                written.append(entry)
            }
        }
        return written
    }

    /// Saves the user's correction to an entry, after the same checks as a new one.
    /// Throws `WriteRejected` and changes nothing if the corrected entry fails them.
    static func update(_ entry: MealEntry, to draft: EntryDraft, in context: ModelContext) throws {
        let found = Integrity.issues(for: draft, origin: .correction(of: entry.source), confirmedByUser: true)
        guard found.isEmpty else { throw WriteRejected(issues: [0: found]) }
        entry.dayKey = draft.date.iso
        entry.mealRaw = draft.meal.rawValue
        entry.foodDescription = draft.description
        entry.calories = draft.calories
        entry.protein = draft.protein
        entry.carbs = draft.carbs
        entry.fat = draft.fat
        entry.containsAlcohol = draft.containsAlcohol
        try context.save()
    }

    static func delete(_ entry: MealEntry, in context: ModelContext) throws {
        context.delete(entry)
        try context.save()
    }
}

/// Targets above the app's limits (#42), whichever screen or card they came from.
struct TargetsRejected: LocalizedError, Equatable {
    let issues: [IntegrityIssue]

    var errorDescription: String? {
        "Daily targets can be at most \(Integrity.maxCalories.formatted()) calories, and at most "
            + "\(Integrity.maxGrams.formatted()) g each of protein, carbs and fat."
    }
}

/// Current and historical targets from the store.
enum TargetStore {
    static func periods(in context: ModelContext) throws -> [TargetPeriod] {
        try context.fetch(FetchDescriptor<Targets>()).map(\.period)
    }

    static func current(on date: LocalDate, in context: ModelContext) throws -> MacroTargets {
        TargetHistory.effective(on: date, in: try periods(in: context))
    }

    /// The goal note of the version in force on `date`, if any.
    static func goalNote(on date: LocalDate, in context: ModelContext) throws -> String {
        try context.fetch(FetchDescriptor<Targets>())
            .filter { $0.period.effectiveFrom <= date }
            .max { $0.effectiveFromKey < $1.effectiveFromKey }?
            .goalNote ?? ""
    }

    /// Records new targets from `date` onward, keeping earlier versions as history.
    /// A second change on the same day edits that day's version instead of adding another.
    /// Setting the targets that already apply is a no-op. Throws `TargetsRejected` and
    /// changes nothing if a value is over the limits.
    static func set(_ targets: MacroTargets, goalNote: String = "", from date: LocalDate,
                    in context: ModelContext) throws {
        let tooLarge = Integrity.sizeIssues(calories: targets.calories, protein: targets.protein,
                                            carbs: targets.carbs, fat: targets.fat)
        guard tooLarge.isEmpty else { throw TargetsRejected(issues: tooLarge) }
        let key = date.iso
        var descriptor = FetchDescriptor<Targets>(predicate: #Predicate { $0.effectiveFromKey == key })
        descriptor.fetchLimit = 1
        if let sameDay = try context.fetch(descriptor).first {
            sameDay.calories = targets.calories
            sameDay.protein = targets.protein
            sameDay.carbs = targets.carbs
            sameDay.fat = targets.fat
            sameDay.goalNote = goalNote
        } else {
            let hasHistory = try context.fetchCount(FetchDescriptor<Targets>()) > 0
            let unchanged = try current(on: date, in: context) == targets
                && TargetStore.goalNote(on: date, in: context) == goalNote
            if hasHistory && unchanged { return }
            context.insert(Targets(effectiveFrom: date, targets: targets, goalNote: goalNote))
        }
        try context.save()
    }
}

/// Day totals across the detail window and rolled-up history.
enum DayTotalsIndex {
    static func build(entries: [MealEntry], summaries: [DailySummary]) -> [LocalDate: NutritionTotals] {
        var result: [LocalDate: NutritionTotals] = [:]
        for summary in summaries where summary.rolledUp {
            result[summary.date, default: .zero] = result[summary.date, default: .zero] + summary.totals
        }
        for (day, group) in Dictionary(grouping: entries, by: \.date) {
            result[day, default: .zero] = result[day, default: .zero] + NutritionTotals(group)
        }
        return result
    }

    static func load(from start: LocalDate, through end: LocalDate,
                     in context: ModelContext) throws -> [LocalDate: NutritionTotals] {
        let lo = start.iso, hi = end.iso
        let entries = try context.fetch(FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.dayKey >= lo && $0.dayKey <= hi }))
        let summaries = try context.fetch(FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.dayKey >= lo && $0.dayKey <= hi }))
        return build(entries: entries, summaries: summaries)
    }
}
