import Foundation

// Shared with the widget extension (target membership in the project file), along with
// `LocalDate.swift`. Keep this file to Foundation only.

/// What the Home Screen widget needs to show calories left (D93). The app works out every
/// number and writes this to the shared App Group, so the widget never opens the database.
/// The widget only decides which day applies at a given moment.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// The day `eaten` belongs to, in the app's time zone.
    var day: LocalDate
    var timeZoneID: String
    /// The calorie target in force on `day`.
    var target: Int
    /// Calories logged for `day`.
    var eaten: Int
    /// The target in force the day after, for when midnight passes before the app runs again.
    var nextTarget: Int

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// What to show at `date`. On the snapshot's day, its own totals. On a later day nothing
    /// has been eaten yet, because logging needs the app, which writes a fresh snapshot.
    /// The latest known target stands in for any day after that.
    func display(at date: Date) -> CaloriesLeft {
        let shown = LocalDate(date, in: timeZone)
        guard shown > day else {
            return CaloriesLeft(day: day, left: Self.difference(target, eaten))
        }
        return CaloriesLeft(day: shown, left: nextTarget)
    }

    /// Moments the widget should redraw by itself: now, then each of the next local midnights.
    func timeline(from now: Date, midnights: Int = 2) -> [(date: Date, value: CaloriesLeft)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        let times = [now] + (1...max(midnights, 1)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
        return times.map { ($0, display(at: $0)) }
    }

    /// `a - b` without trapping on numbers past the entry limits.
    private static func difference(_ a: Int, _ b: Int) -> Int {
        let (value, overflow) = a.subtractingReportingOverflow(b)
        return overflow ? (b > 0 ? .min : .max) : value
    }
}

/// One day's line on the widget. Negative `left` means over target.
struct CaloriesLeft: Equatable, Sendable {
    var day: LocalDate
    var left: Int

    var isOver: Bool { left < 0 }
    /// The number shown, always positive; the unit says whether it's left or over.
    var shown: Int { left == .min ? .max : abs(left) }
    var unit: String { isOver ? "cal over" : "cal left" }
    var spoken: String { "\(shown.formatted()) calories \(isOver ? "over target" : "left") today" }
}

/// Where the app and the widget meet: the App Group's shared preferences (D93).
enum WidgetShare {
    static let appGroup = "group.com.untetheredcitizens.calories"
    static let snapshotKey = "widgetSnapshot"
    /// The widget's kind, used to reload just this widget.
    static let caloriesKind = "CaloriesLeft"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func read(from defaults: UserDefaults? = WidgetShare.defaults) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Saves `snapshot`. Returns false when it matched what was already saved, so the caller
    /// can skip asking the widget to redraw.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot, to defaults: UserDefaults? = WidgetShare.defaults) -> Bool {
        guard let defaults, read(from: defaults) != snapshot,
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }
}

/// The link the widget opens (D94): the Log tab, ready to type.
enum WidgetLink {
    static let scheme = "untetheredcalories"
    static let log = URL(string: "\(scheme)://log")!

    static func opensLog(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host()?.lowercased() == "log"
    }
}
