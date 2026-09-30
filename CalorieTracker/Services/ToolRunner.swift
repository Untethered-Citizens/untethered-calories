import Foundation
import SwiftData

/// Something the user must tap before anything is written.
enum ProposalKind: Sendable {
    /// Path B: the model's estimate, awaiting Accept or Edit.
    case estimate([PendingEntry])
    case targets(MacroTargets, from: LocalDate, goalNote: String)
    case usualMeal(UsualMealInput, meal: Meal, source: Source, replacesExisting: Bool)
}

/// What running one tool call did.
struct ToolOutcome: Sendable {
    enum Effect: Sendable {
        /// A read: the model needs the result to carry on.
        case none
        /// Path A entries were written. `line` is the confirmation the user sees.
        case logged(line: String)
        case proposal(ProposalKind)
    }

    var text: String
    var isError = false
    var effect: Effect = .none

    static func error(_ text: String) -> ToolOutcome { ToolOutcome(text: text, isError: true) }

    /// A finished action (a write or a card). The model doesn't need to hear about it
    /// until the user's next message, which saves a round trip.
    var isTerminal: Bool {
        if isError { return false }
        if case .none = effect { return false }
        return true
    }
}

/// Runs the model's tool calls against the local store. The model proposes; this code
/// decides. Every write still passes `EntryWriter`, the single write boundary.
@MainActor
struct ToolRunner {
    let context: ModelContext
    let today: LocalDate
    /// True once a photo has been sent in this conversation, so a "label photo" can be real.
    let conversationHasPhoto: Bool
    var text = LogText()

    static let cardShown = "Shown to the user as a card. Nothing is written until they tap it. You'll be told the outcome in their next message."

    func run(_ call: ToolCall) -> ToolOutcome {
        guard let tool = LogTool(rawValue: call.name) else {
            return .error("Unknown tool \(call.name).")
        }
        do {
            switch tool {
            case .logEntries: return try logEntries(call.input.decode(EntriesInput.self))
            case .proposeEstimate: return try proposeEstimate(call.input.decode(EntriesInput.self))
            case .getDay: return try getDay(call.input.decode(DayInput.self))
            case .getRangeSummary: return try getRange(call.input.decode(RangeInput.self))
            case .proposeTargets: return try proposeTargets(call.input.decode(TargetsInput.self))
            case .addUsualMeal: return try addUsualMeal(call.input.decode(UsualMealInput.self))
            }
        } catch let error as DecodingError {
            return .error("The input didn't match the schema: \(Self.describe(error))")
        } catch {
            return .error("The app couldn't do that: \(error.localizedDescription)")
        }
    }

    // MARK: Logging

    private func logEntries(_ input: EntriesInput) throws -> ToolOutcome {
        guard !input.entries.isEmpty else { return .error("No entries were given.") }
        let pending: [PendingEntry]
        switch resolve(input.entries, allowed: EntryBasis.pathA) {
        case .failure(let failure): return .error(failure.message)
        case .success(let resolved): pending = resolved
        }
        do {
            try EntryWriter.commit(pending, confirmedByUser: false, in: context)
            try context.save()
        } catch let rejected as WriteRejected {
            return .error(Self.describe(rejected, entries: pending))
        }
        let line = try confirmation(for: pending.map(\.draft))
        return ToolOutcome(text: "Logged. The app showed the user: \"\(line)\"", effect: .logged(line: line))
    }

    private func proposeEstimate(_ input: EntriesInput) throws -> ToolOutcome {
        guard !input.entries.isEmpty else { return .error("No entries were given.") }
        let pending: [PendingEntry]
        switch resolve(input.entries, allowed: EntryBasis.pathB) {
        case .failure(let failure): return .error(failure.message)
        case .success(let resolved): pending = resolved
        }
        // Check everything except the confirmation itself, which is the user's tap.
        var problems: [Int: [IntegrityIssue]] = [:]
        for (index, entry) in pending.enumerated() {
            let found = Integrity.issues(for: entry.draft, origin: entry.origin, confirmedByUser: true)
            if !found.isEmpty { problems[index] = found }
        }
        if !problems.isEmpty {
            return .error(Self.describe(WriteRejected(issues: problems), entries: pending))
        }
        return ToolOutcome(text: Self.cardShown, effect: .proposal(.estimate(pending)))
    }

    /// Turns the model's entries into drafts with their origin, or says what's wrong.
    private func resolve(_ entries: [ToolEntry], allowed: [EntryBasis]) -> Result<[PendingEntry], ToolFailure> {
        var result: [PendingEntry] = []
        for (index, entry) in entries.enumerated() {
            let label = "Entry \(index + 1) (\"\(entry.description)\")"
            guard allowed.contains(entry.basis) else {
                return .failure(ToolFailure("\(label): basis \(entry.basis.rawValue) isn't allowed in this tool."))
            }
            guard let date = LocalDate(iso: entry.date) else {
                return .failure(ToolFailure("\(label): date must be YYYY-MM-DD, got \"\(entry.date)\"."))
            }
            guard date <= today else {
                return .failure(ToolFailure("\(label): \(date.iso) is in the future. Today is \(today.iso)."))
            }
            guard let meal = Meal(rawValue: entry.meal) else {
                return .failure(ToolFailure("\(label): meal must be Breakfast, Lunch, Dinner or Snack."))
            }
            guard let source = Source(rawValue: entry.source) else {
                return .failure(ToolFailure("\(label): source must be Label, Estimate or Photo Estimate."))
            }
            if [.labelPhoto, .foodPhoto].contains(entry.basis) && !conversationHasPhoto {
                return .failure(ToolFailure("\(label): basis \(entry.basis.rawValue) needs a photo, and none was sent in this conversation."))
            }
            if entry.basis == .usualMeal {
                guard let usual = findUsualMeal(entry.usualMealName) else {
                    return .failure(ToolFailure("\(label): there's no usual meal called \"\(entry.usualMealName)\". Saved: \(usualMealNames())."))
                }
                // The stored numbers and source win over whatever the model sent.
                result.append(PendingEntry(draft: usual.draft(on: date, meal: meal),
                                           origin: .usualMeal(storedSource: usual.source)))
                continue
            }
            let draft = EntryDraft(date: date, meal: meal,
                                   description: entry.description.trimmingCharacters(in: .whitespacesAndNewlines),
                                   calories: entry.calories, protein: entry.protein, carbs: entry.carbs,
                                   fat: entry.fat, source: source, containsAlcohol: entry.containsAlcohol)
            result.append(PendingEntry(draft: draft, origin: entry.basis.origin(usualMealSource: nil)))
        }
        return .success(result)
    }

    func confirmation(for drafts: [EntryDraft]) throws -> String {
        let days = Set(drafts.map(\.date))
        var totals: [LocalDate: NutritionTotals] = [:]
        for day in days {
            totals[day] = try DayTotalsIndex.load(from: day, through: day, in: context)[day] ?? .zero
        }
        let periods = try TargetStore.periods(in: context)
        return text.confirmation(entries: drafts, today: today, dayTotals: totals,
                                 targets: { TargetHistory.effective(on: $0, in: periods) })
    }

    // MARK: Reads

    private func getDay(_ input: DayInput) throws -> ToolOutcome {
        guard let day = LocalDate(iso: input.date) else { return .error("date must be YYYY-MM-DD.") }
        let key = day.iso
        let entries = try context.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.dayKey == key }))
            .sorted(by: MealEntry.detailOrder)
        let summary = try DailySummaryStore.find(day, in: context)
        let target = try TargetStore.current(on: day, in: context)
        let totals = try DayTotalsIndex.load(from: day, through: day, in: context)[day] ?? .zero

        var lines = ["\(LogContext.dayLabel(day))\(day == today ? " (today, still in progress)" : "")"]
        lines.append("Targets that day: \(target.calories) kcal, \(target.protein)p/\(target.carbs)c/\(target.fat)f")
        if totals.entryCount == 0 {
            lines.append("No food logged for this day.")
        } else {
            if let summary, summary.rolledUp, !summary.mealsDetail.isEmpty {
                lines.append("Entries (from the day's summary):")
                lines += summary.mealsDetail.split(separator: "\n").map { "- \($0)" }
            }
            if !entries.isEmpty {
                lines.append("Entries:")
                lines += entries.map { "- " + RollUp.detailLine($0) }
            }
            var total = "Totals: \(totals.calories) kcal, \(totals.protein)p/\(totals.carbs)c/\(totals.fat)f"
            if let share = totals.estimatedPercent { total += ", \(share)% of calories estimated" }
            lines.append(total)
        }
        if let weight = summary?.weight { lines.append("Weight: \(String(format: "%.1f", weight)) lb") }
        return ToolOutcome(text: lines.joined(separator: "\n"))
    }

    private func getRange(_ input: RangeInput) throws -> ToolOutcome {
        guard let from = LocalDate(iso: input.from), let to = LocalDate(iso: input.to) else {
            return .error("from and to must be YYYY-MM-DD.")
        }
        guard from <= to else { return .error("from must be on or before to.") }
        guard from.days(until: to) < 92 else { return .error("The range can be at most 92 days.") }

        let totals = try DayTotalsIndex.load(from: from, through: to, in: context)
        let lo = from.iso, hi = to.iso
        let summaries = try context.fetch(FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.dayKey >= lo && $0.dayKey <= hi }))
        let weights = Dictionary(summaries.compactMap { s in s.weight.map { (s.date, $0) } }, uniquingKeysWith: { a, _ in a })
        let periods = try TargetStore.periods(in: context)

        var lines = ["Days \(from.iso) to \(to.iso):"]
        var complete: [NutritionTotals] = []
        var gaps: [LocalDate] = []
        for day in LocalDate.range(from: from, through: to) {
            let target = TargetHistory.effective(on: day, in: periods).calories
            var line = "\(day.iso): "
            if let t = totals[day], t.entryCount > 0 {
                line += "\(t.calories) kcal, \(t.protein)p/\(t.carbs)c/\(t.fat)f"
                if let share = t.estimatedPercent { line += ", \(share)% estimated" }
                line += ", target \(target)"
                if day == today { line += " (today, partial)" } else if day < today { complete.append(t) }
            } else {
                line += "no data"
                if day < today { gaps.append(day) }
            }
            if let weight = weights[day] { line += ", weight \(String(format: "%.1f", weight)) lb" }
            lines.append(line)
        }
        if complete.isEmpty {
            lines.append("No complete days with data, so no averages.")
        } else {
            let sum = complete.reduce(NutritionTotals.zero, +)
            let n = Double(complete.count)
            lines.append("Average over \(complete.count) complete days (gaps and today left out): "
                + "\(Rounding.nearest5(Double(sum.calories) / n)) kcal, "
                + "\(Int((Double(sum.protein) / n).rounded()))p/\(Int((Double(sum.carbs) / n).rounded()))c/\(Int((Double(sum.fat) / n).rounded()))f"
                + (sum.estimatedPercent.map { ", \($0)% of calories estimated" } ?? ""))
        }
        if !gaps.isEmpty { lines.append("Days with no data: \(gaps.count).") }
        return ToolOutcome(text: lines.joined(separator: "\n"))
    }

    // MARK: Cards

    private func proposeTargets(_ input: TargetsInput) throws -> ToolOutcome {
        guard let from = LocalDate(iso: input.effectiveFrom) else { return .error("effective_from must be YYYY-MM-DD.") }
        guard from >= today else {
            return .error("effective_from can't be in the past (today is \(today.iso)); past days keep the targets they had.")
        }
        guard input.calories > 0, input.protein >= 0, input.carbs >= 0, input.fat >= 0 else {
            return .error("Calories must be above zero and macros can't be negative.")
        }
        let targets = MacroTargets(calories: input.calories, protein: input.protein, carbs: input.carbs, fat: input.fat)
        return ToolOutcome(text: Self.cardShown,
                           effect: .proposal(.targets(targets, from: from, goalNote: input.goalNote)))
    }

    private func addUsualMeal(_ input: UsualMealInput) throws -> ToolOutcome {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .error("name can't be empty.") }
        guard let meal = Meal(rawValue: input.meal) else { return .error("meal must be Breakfast, Lunch, Dinner or Snack.") }
        guard let source = Source(rawValue: input.source) else { return .error("source must be Label, Estimate or Photo Estimate.") }
        let draft = EntryDraft(date: today, meal: meal, description: input.description,
                               calories: input.calories, protein: input.protein, carbs: input.carbs,
                               fat: input.fat, source: source, containsAlcohol: input.containsAlcohol)
        if let issue = Integrity.macroIssue(draft), case .macroMismatch(let stated, let macros) = issue {
            return .error("4×protein + 4×carbs + 9×fat = \(macros) kcal, but calories = \(stated). Fix the numbers (or set contains_alcohol).")
        }
        var cleaned = input
        cleaned.name = name
        return ToolOutcome(text: Self.cardShown,
                           effect: .proposal(.usualMeal(cleaned, meal: meal, source: source,
                                                        replacesExisting: findUsualMeal(name) != nil)))
    }

    // MARK: Helpers

    func findUsualMeal(_ name: String) -> UsualMeal? {
        let wanted = Self.normalise(name)
        guard !wanted.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<UsualMeal>())) ?? []
        return all.first { Self.normalise($0.name) == wanted }
            ?? all.first { $0.triggerPhrases.map(Self.normalise).contains(wanted) }
    }

    private func usualMealNames() -> String {
        let names = ((try? context.fetch(FetchDescriptor<UsualMeal>())) ?? []).map { "\"\($0.name)\"" }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    static func normalise(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    static func describe(_ rejected: WriteRejected, entries: [PendingEntry]) -> String {
        var lines = ["Nothing was written. Fix these and call again:"]
        for index in rejected.issues.keys.sorted() {
            let label = "Entry \(index + 1) (\"\(entries[index].draft.description)\")"
            for issue in rejected.issues[index]! {
                switch issue {
                case .emptyDescription:
                    lines.append("\(label): description is empty.")
                case .negativeValue(let field):
                    lines.append("\(label): \(field) is negative.")
                case .macroMismatch(let stated, let macros):
                    lines.append("\(label): 4×protein + 4×carbs + 9×fat = \(macros) kcal, but calories = \(stated), more than 15% apart. Values may be in the wrong fields. If it contains alcohol, set contains_alcohol.")
                case .sourceMismatch(let expected, let got):
                    lines.append("\(label): this basis needs source \"\(expected.rawValue)\", not \"\(got.rawValue)\".")
                case .needsConfirmation:
                    lines.append("\(label): this is an estimate, so use propose_estimate and let the user confirm.")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): "missing field \(key.stringValue)."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            "\(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        @unknown default: "\(error)"
        }
    }
}

struct ToolFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
