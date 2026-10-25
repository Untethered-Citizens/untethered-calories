import Foundation

/// One body-mass sample as Apple Health reports it, already converted to pounds.
struct WeightSample: Equatable, Sendable {
    /// When the weigh-in happened.
    var taken: Date
    var pounds: Double
}

/// Turns Health samples into one reading per calendar day (D20, D49).
enum WeightImport {
    /// How far back the sync looks, and so how much history the first connection brings in.
    static let windowDays = 90

    /// The latest weigh-in on each local calendar day, to one decimal. A reading belongs to
    /// the day it was taken, not to today. Any app can write to Health, so readings outside
    /// the range a typed weight must fall in are ignored, as if they weren't there (#46).
    static func dailyLatest(_ samples: [WeightSample], in timeZone: TimeZone) -> [LocalDate: Double] {
        var latest: [LocalDate: WeightSample] = [:]
        for sample in samples where sample.pounds.isFinite && WeightEntry.plausiblePounds.contains(sample.pounds) {
            let day = LocalDate(sample.taken, in: timeZone)
            if let kept = latest[day], kept.taken >= sample.taken { continue }
            latest[day] = sample
        }
        return latest.mapValues { ($0.pounds * 10).rounded() / 10 }
    }

    /// The first day the sync covers, counting today as day one.
    static func windowStart(today: LocalDate) -> LocalDate {
        today.adding(days: -(windowDays - 1))
    }
}

/// A weight typed into the app, on its way to Apple Health.
enum WeightEntry {
    /// Anything outside this is a typo, not a weight.
    static let plausiblePounds = 50.0...700.0

    /// The typed value in `unit`, if it reads as a plausible weight. Accepts "," or "." as
    /// the decimal mark.
    static func value(from text: String, unit: WeightUnit) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite,
              plausiblePounds.contains(unit.toPounds(value)) else { return nil }
        return value
    }
}
