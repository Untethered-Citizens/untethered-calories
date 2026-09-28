import Foundation
import SwiftData

/// One food item or meal as logged. Lives in the rolling detail window, then is
/// rolled up into its day's `DailySummary` and deleted.
@Model
final class MealEntry {
    #Index<MealEntry>([\.dayKey])

    var id: UUID
    /// The local day eaten, as "YYYY-MM-DD". Stored as text so it sorts and filters
    /// without any time zone involved.
    var dayKey: String
    var mealRaw: String
    var foodDescription: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var sourceRaw: String
    var containsAlcohol: Bool
    /// Audit only. Never used for ordering.
    var createdAt: Date

    init(_ draft: EntryDraft, createdAt: Date = Date()) {
        id = UUID()
        dayKey = draft.date.iso
        mealRaw = draft.meal.rawValue
        foodDescription = draft.description
        calories = draft.calories
        protein = draft.protein
        carbs = draft.carbs
        fat = draft.fat
        sourceRaw = draft.source.rawValue
        containsAlcohol = draft.containsAlcohol
        self.createdAt = createdAt
    }

    var date: LocalDate { LocalDate(iso: dayKey)! }
    var meal: Meal { Meal(rawValue: mealRaw) ?? .snack }
    var source: Source { Source(rawValue: sourceRaw) ?? .estimate }

    /// Detail order: date, then meal slot, then creation as a tiebreak within a slot.
    static func detailOrder(_ a: MealEntry, _ b: MealEntry) -> Bool {
        if a.dayKey != b.dayKey { return a.dayKey < b.dayKey }
        if a.meal != b.meal { return a.meal < b.meal }
        return a.createdAt < b.createdAt
    }
}

extension MealEntry: NutritionItem {}
