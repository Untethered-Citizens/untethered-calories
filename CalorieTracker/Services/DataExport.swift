import Foundation
import SwiftData

/// Writes everything on the phone to two CSV files for the share sheet (D52).
enum DataExport {
    static func files(from context: ModelContext, unit: WeightUnit, today: LocalDate) throws -> [URL] {
        let entries = try context.fetch(FetchDescriptor<MealEntry>()).sorted(by: MealEntry.detailOrder)
        let summaries = try context.fetch(FetchDescriptor<DailySummary>())

        let totals = DayTotalsIndex.build(entries: entries, summaries: summaries)
        let byDay = Dictionary(grouping: entries, by: \.date)
        let summaryByDay = Dictionary(summaries.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let days = Set(totals.keys).union(summaryByDay.keys).map { day in
            let folded = summaryByDay[day].map { $0.mealsDetail.split(separator: "\n").map(String.init) } ?? []
            return CSVExport.Day(date: day, totals: totals[day] ?? .zero,
                                 weightPounds: summaryByDay[day]?.weight,
                                 mealLines: folded + (byDay[day] ?? []).map(RollUp.detailLine))
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Calorie Tracker export \(today.iso)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let meals = folder.appendingPathComponent("meals.csv")
        let daily = folder.appendingPathComponent("daily.csv")
        try CSVExport.meals(entries.map(\.draft)).write(to: meals, atomically: true, encoding: .utf8)
        try CSVExport.daily(days, unit: unit).write(to: daily, atomically: true, encoding: .utf8)
        return [daily, meals]
    }
}

/// Daily totals older than the retention setting. Deleting them is the one step that loses
/// data, so it only ever happens from the prompt, never on its own (D52).
enum Retention {
    /// How often the prompt may come back after "Not now".
    static let promptIntervalDays = 30

    static func cutoff(today: LocalDate, keepDays: Int) -> LocalDate {
        today.adding(days: -keepDays)
    }

    static func due(today: LocalDate, keepDays: Int?, in context: ModelContext) throws -> [DailySummary] {
        guard let keepDays else { return [] }
        let key = cutoff(today: today, keepDays: keepDays).iso
        return try context.fetch(FetchDescriptor<DailySummary>(predicate: #Predicate { $0.dayKey < key }))
    }

    static func shouldPrompt(dueCount: Int, lastPrompt: LocalDate?, today: LocalDate) -> Bool {
        guard dueCount > 0 else { return false }
        guard let lastPrompt else { return true }
        return lastPrompt.days(until: today) >= promptIntervalDays
    }

    /// Deletes the due rows (and any stray meal detail on those days) in one transaction.
    @discardableResult
    static func prune(today: LocalDate, keepDays: Int, in context: ModelContext) throws -> Int {
        let key = cutoff(today: today, keepDays: keepDays).iso
        var count = 0
        try context.transaction {
            let rows = try context.fetch(FetchDescriptor<DailySummary>(predicate: #Predicate { $0.dayKey < key }))
            let stray = try context.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.dayKey < key }))
            rows.forEach(context.delete)
            stray.forEach(context.delete)
            count = rows.count
        }
        return count
    }
}
