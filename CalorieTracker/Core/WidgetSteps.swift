import Foundation

// Shared with the widget extension, like `WidgetSnapshot.swift`. Foundation only.

/// Today's step count as last read from Apple Health (#16, D95). Health is locked while the
/// phone is, so the widget keeps its last good reading here and shows it until it can read again.
struct StepsReading: Codable, Equatable, Sendable {
    var day: LocalDate
    var count: Int
}

/// What the widget's steps line says.
enum StepsShown: Equatable, Sendable {
    case count(Int)
    /// Health can't be read right now (phone locked) and there's no reading for today yet.
    case unknown
    /// The app hasn't asked for Steps yet, so there's nothing to read.
    case notAsked

    /// Picks the honest value: a fresh reading, else today's cached one, else a gap.
    /// A reading from an earlier day is never shown as today's.
    static func pick(fresh: Int?, cached: StepsReading?, today: LocalDate, asked: Bool) -> StepsShown {
        guard asked else { return .notAsked }
        if let fresh { return .count(max(fresh, 0)) }
        if let cached, cached.day == today { return .count(max(cached.count, 0)) }
        return .unknown
    }

    var number: String {
        switch self {
        case .count(let steps): steps.formatted()
        case .unknown, .notAsked: "–"
        }
    }

    /// The label under the number. Before Steps are allowed, it says how to allow them
    /// (tapping the widget opens the app, which asks).
    var unit: String { self == .notAsked ? "tap to allow steps" : "steps" }

    var spoken: String {
        switch self {
        case .count(let steps): "\(steps.formatted()) steps today"
        case .unknown: "Steps will show when your iPhone is unlocked"
        case .notAsked: "Open Untethered Calories to allow Steps"
        }
    }
}

extension WidgetShare {
    static let stepsKey = "widgetSteps"

    static func readSteps(from defaults: UserDefaults? = WidgetShare.defaults) -> StepsReading? {
        guard let data = defaults?.data(forKey: stepsKey) else { return nil }
        return try? JSONDecoder().decode(StepsReading.self, from: data)
    }

    static func writeSteps(_ reading: StepsReading, to defaults: UserDefaults? = WidgetShare.defaults) {
        guard let data = try? JSONEncoder().encode(reading) else { return }
        defaults?.set(data, forKey: stepsKey)
    }
}
