import Foundation

/// The daily measuring stick.
struct MacroTargets: Equatable, Codable, Sendable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    static let defaults = MacroTargets(calories: 1785, protein: 145, carbs: 165, fat: 60)
}

/// One version of the targets, in force from `effectiveFrom` until the next version.
struct TargetPeriod: Equatable, Sendable {
    var effectiveFrom: LocalDate
    var targets: MacroTargets
}

enum TargetHistory {
    /// The targets that applied on `date`, so a past day is judged by its own targets
    /// and not re-judged against today's.
    /// Before the first period, the earliest known targets are the best guess.
    /// With no history at all, the defaults apply.
    static func effective(on date: LocalDate, in periods: [TargetPeriod]) -> MacroTargets {
        let sorted = periods.sorted { $0.effectiveFrom < $1.effectiveFrom }
        if let match = sorted.last(where: { $0.effectiveFrom <= date }) { return match.targets }
        return sorted.first?.targets ?? .defaults
    }
}
