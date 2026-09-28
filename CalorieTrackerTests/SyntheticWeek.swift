import Foundation
@testable import CalorieTracker

/// A synthetic week shaped like the pilot week (Sep 19–25), for tests only.
/// Foods and numbers are invented. No real user data.
/// "Today" is Sep 26, which has a partial day logged. Sep 23 is a deliberate gap.
enum SyntheticWeek {
    static let today = d("2026-09-26")
    static let firstDay = d("2026-09-19")
    static let gapDay = d("2026-09-23")

    static func d(_ iso: String) -> LocalDate { LocalDate(iso: iso)! }

    /// Calories derived from the macros (rounded to 5), so every non-alcohol entry is consistent.
    static func e(_ day: String, _ meal: Meal, _ text: String,
                  _ p: Int, _ c: Int, _ f: Int, _ source: Source) -> EntryDraft {
        EntryDraft(date: d(day), meal: meal, description: text,
                   calories: Rounding.nearest5(Double(Integrity.macroCalories(protein: p, carbs: c, fat: f))),
                   protein: p, carbs: c, fat: f, source: source)
    }

    static let entries: [EntryDraft] = [
        e("2026-09-19", .dinner, "Veggie stir-fry with rice", 18, 70, 16, .estimate),
        e("2026-09-19", .snack, "Handful of almonds", 6, 6, 14, .estimate),

        e("2026-09-20", .breakfast, "Yogurt with granola", 17, 26, 19, .label),
        e("2026-09-20", .lunch, "Lentil soup and bread", 20, 60, 10, .estimate),
        e("2026-09-20", .dinner, "Pasta with tomato sauce", 22, 95, 18, .photoEstimate),
        e("2026-09-20", .snack, "Apple", 0, 25, 0, .estimate),
        EntryDraft(date: d("2026-09-20"), meal: .dinner, description: "Glass of red wine",
                   calories: 125, protein: 0, carbs: 4, fat: 0, source: .estimate, containsAlcohol: true),

        e("2026-09-21", .breakfast, "Yogurt with granola", 17, 26, 19, .label),
        e("2026-09-21", .lunch, "Frozen curry meal", 14, 66, 19, .label),
        e("2026-09-21", .dinner, "Tofu and roasted vegetables", 28, 30, 24, .estimate),
        e("2026-09-21", .snack, "Protein bar", 20, 22, 8, .label),

        e("2026-09-22", .breakfast, "Oatmeal with banana", 12, 60, 9, .estimate),
        e("2026-09-22", .lunch, "Bean burrito", 22, 80, 22, .photoEstimate),
        e("2026-09-22", .dinner, "Cauliflower gratin", 14, 20, 30, .estimate),
        e("2026-09-22", .dinner, "Baked tofu", 20, 6, 12, .estimate),
        e("2026-09-22", .snack, "Dark chocolate", 2, 14, 12, .estimate),

        // 2026-09-23: no data (gap)

        e("2026-09-24", .breakfast, "Yogurt with granola", 17, 26, 19, .label),
        e("2026-09-24", .lunch, "Salad kit with chickpeas", 14, 36, 26, .estimate),
        e("2026-09-24", .dinner, "Veggie pizza, two slices", 24, 70, 24, .photoEstimate),
        e("2026-09-24", .snack, "Popcorn", 3, 30, 6, .estimate),

        e("2026-09-25", .breakfast, "Toast with peanut butter", 12, 30, 16, .estimate),
        e("2026-09-25", .lunch, "Frozen curry meal", 14, 66, 19, .label),
        e("2026-09-25", .dinner, "Black bean tacos", 24, 64, 20, .estimate),
        e("2026-09-25", .snack, "Hummus and carrots", 6, 20, 10, .estimate),

        // Today, in progress.
        e("2026-09-26", .breakfast, "Yogurt with granola", 17, 26, 19, .label),
        e("2026-09-26", .lunch, "Grain bowl", 20, 65, 18, .estimate),
    ]

    static let weights: [(LocalDate, Double)] = [
        (d("2026-09-20"), 172.4), (d("2026-09-23"), 171.8), (d("2026-09-26"), 171.6),
    ]

    /// Origin that matches each entry's source, for writing through the checked boundary.
    static func origin(for draft: EntryDraft) -> EntryOrigin {
        switch draft.source {
        case .label: return .statedNumbers
        case .estimate: return .description
        case .photoEstimate: return .foodPhoto
        }
    }
}
