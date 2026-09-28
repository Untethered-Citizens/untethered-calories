import Foundation

/// The meal slot. Declaration order is the display and sort order.
enum Meal: String, CaseIterable, Codable, Comparable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    var sortOrder: Int { Self.allCases.firstIndex(of: self)! }

    static func < (lhs: Meal, rhs: Meal) -> Bool { lhs.sortOrder < rhs.sortOrder }
}

/// Where an entry's numbers came from. An estimate is never promoted to a label.
enum Source: String, CaseIterable, Codable, Sendable {
    case label = "Label"
    case estimate = "Estimate"
    case photoEstimate = "Photo Estimate"

    /// True for anything that isn't read off a label. Drives the honesty stats.
    var isEstimated: Bool { self != .label }
}

/// Anything carrying the four numbers and a source: drafts, stored entries, usual meals.
protocol NutritionItem {
    var calories: Int { get }
    var protein: Int { get }
    var carbs: Int { get }
    var fat: Int { get }
    var source: Source { get }
    var containsAlcohol: Bool { get }
}

/// An entry before it is written: what the model proposes or the user edits.
/// Every value is a named field, never a position in a list (pilot lesson 1).
struct EntryDraft: NutritionItem, Equatable, Codable, Sendable {
    var date: LocalDate
    var meal: Meal
    var description: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var source: Source
    var containsAlcohol: Bool = false
}
