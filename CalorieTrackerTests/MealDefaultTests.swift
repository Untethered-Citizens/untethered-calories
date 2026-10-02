import Foundation
import Testing
@testable import CalorieTracker

struct MealDefaultTests {
    let la = TimeZone(identifier: "America/Los_Angeles")!

    func at(_ hhmm: String) -> Date {
        // Sep 29, 2026 is PDT (UTC−7).
        ISO8601DateFormatter().date(from: "2026-09-29T\(hhmm):00-07:00")!
    }

    @Test(arguments: [
        ("03:59", Meal.snack), ("04:00", .breakfast), ("10:29", .breakfast),
        ("10:30", .lunch), ("13:52", .lunch), ("14:59", .lunch),
        ("15:00", .snack), ("16:59", .snack), ("17:00", .dinner),
        ("20:59", .dinner), ("21:00", .snack), ("23:30", .snack),
    ])
    func windowsFollowTheLocalClock(_ time: String, _ expected: Meal) {
        #expect(Meal.default(at: at(time), in: la) == expected)
    }

    @Test func usesTheDeviceTimeZoneNotUTC() {
        // 13:00 in Los Angeles is 20:00 UTC: lunch there, dinner in UTC.
        let instant = at("13:00")
        #expect(Meal.default(at: instant, in: la) == .lunch)
        #expect(Meal.default(at: instant, in: TimeZone(identifier: "UTC")!) == .dinner)
    }
}
