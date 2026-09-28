import Foundation

/// A calendar day as the user lives it ("2026-09-26"), deliberately not a timestamp.
///
/// Food is logged against the day it was eaten in the user's time zone, so a late-night
/// log never slips into tomorrow and back-dating is just picking another `LocalDate`.
/// All arithmetic runs on a fixed UTC Gregorian calendar, which has no DST jumps.
struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Self.calendar.date(from: components) else { return nil }
        let back = Self.calendar.dateComponents([.year, .month, .day], from: date)
        // Reject values the calendar would silently roll over, like Feb 30.
        guard back.year == year, back.month == month, back.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD".
    init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The calendar day that `date` falls on in `timeZone`.
    init(_ date: Date, in timeZone: TimeZone = .current) {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let c = local.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> LocalDate {
        LocalDate(now, in: timeZone)
    }

    /// "YYYY-MM-DD". Sorts correctly as a plain string, which is how it is stored.
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { iso }

    func adding(days: Int) -> LocalDate {
        let shifted = Self.calendar.date(byAdding: .day, value: days, to: anchor)!
        return LocalDate(shifted, in: Self.utc)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    func days(until other: LocalDate) -> Int {
        Self.calendar.dateComponents([.day], from: anchor, to: other.anchor).day!
    }

    /// Every day from `start` through `end`, inclusive. Empty if `end` is before `start`.
    static func range(from start: LocalDate, through end: LocalDate) -> [LocalDate] {
        let count = start.days(until: end)
        guard count >= 0 else { return [] }
        return (0...count).map { start.adding(days: $0) }
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalDate(iso: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Expected YYYY-MM-DD, got \(string)"))
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    private static let utc = TimeZone(identifier: "UTC")!
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }()

    /// Midnight UTC of this day, used only for arithmetic.
    private var anchor: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
