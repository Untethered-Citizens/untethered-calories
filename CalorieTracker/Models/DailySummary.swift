import Foundation
import SwiftData

/// One row per calendar day: totals after roll-up, plus the day's weight.
///
/// Always reach it through `DailySummaryStore.getOrCreate`. The unique constraint is
/// a backstop only: on a clash SwiftData silently merges the rows, which is exactly the
/// "upsert on date" failure the pilot hit. So code must never rely on it.
@Model
final class DailySummary {
    @Attribute(.unique) var dayKey: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    /// Calories from non-Label entries, so honesty stats survive the roll-up.
    var estimatedCalories: Int
    var entryCount: Int
    /// Pounds, one decimal. Nil until a reading exists for this day.
    var weight: Double?
    /// True when `weight` came from Apple Health, so the sync may correct or clear it.
    var weightFromHealth: Bool = false
    /// The day's meals, one line each, written at roll-up.
    var mealsDetail: String
    /// Whether this day's meal detail has been folded in.
    var rolledUp: Bool

    init(date: LocalDate) {
        dayKey = date.iso
        calories = 0
        protein = 0
        carbs = 0
        fat = 0
        estimatedCalories = 0
        entryCount = 0
        weight = nil
        weightFromHealth = false
        mealsDetail = ""
        rolledUp = false
    }

    var date: LocalDate { LocalDate(iso: dayKey)! }

    /// Rolled-up totals. Zero for a row that only holds a weight.
    var totals: NutritionTotals {
        guard rolledUp else { return .zero }
        return NutritionTotals(calories: calories, protein: protein, carbs: carbs, fat: fat,
                               estimatedCalories: estimatedCalories, entryCount: entryCount)
    }
}
