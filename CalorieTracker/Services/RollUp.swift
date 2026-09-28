import Foundation
import SwiftData

/// Folds meal detail older than the window into one `DailySummary` per day, then
/// deletes the detail. Deterministic, no model call, one transaction: if anything
/// fails, nothing is deleted.
enum RollUp {
    struct Result: Equatable {
        var daysRolled: [LocalDate] = []
        var entriesDeleted = 0
    }

    /// Rolls up entries dated more than `detailWindowDays` before `today`.
    /// With a 14-day window on Sep 27, Sep 13 is kept and Sep 12 and older roll up.
    @discardableResult
    static func run(in context: ModelContext, today: LocalDate, detailWindowDays: Int) throws -> Result {
        let cutoff = today.adding(days: -detailWindowDays).iso
        var result = Result()

        try context.transaction {
            let old = try context.fetch(FetchDescriptor<MealEntry>(
                predicate: #Predicate { $0.dayKey < cutoff }))
            guard !old.isEmpty else { return }

            let byDay = Dictionary(grouping: old, by: \.date)
            for day in byDay.keys.sorted() {
                let entries = byDay[day]!.sorted(by: MealEntry.detailOrder)
                let summary = try DailySummaryStore.getOrCreate(day, in: context)
                // A back-dated entry can land on a day that was already rolled up.
                // Add to that row rather than overwrite it.
                let base = summary.totals
                let totals = base + NutritionTotals(entries)
                summary.calories = totals.calories
                summary.protein = totals.protein
                summary.carbs = totals.carbs
                summary.fat = totals.fat
                summary.estimatedCalories = totals.estimatedCalories
                summary.entryCount = totals.entryCount
                let lines = entries.map(detailLine)
                summary.mealsDetail = ([summary.mealsDetail].filter { !$0.isEmpty } + lines)
                    .joined(separator: "\n")
                summary.rolledUp = true
                result.daysRolled.append(day)
            }
            // The detail is written above, before anything is deleted.
            for entry in old { context.delete(entry) }
            result.entriesDeleted = old.count
        }
        return result
    }

    /// `Breakfast — Oatmeal with banana (420 cal, 14p/58c/15f) [Estimate]`
    static func detailLine(_ entry: MealEntry) -> String {
        var line = "\(entry.meal.rawValue) — \(entry.foodDescription) " +
            "(\(entry.calories) cal, \(entry.protein)p/\(entry.carbs)c/\(entry.fat)f) [\(entry.source.rawValue)]"
        if entry.containsAlcohol { line += " [Alcohol]" }
        return line
    }
}
