import Foundation
import Testing
@testable import CalorieTracker

struct LocalDateTests {
    @Test func parsesAndFormatsISO() throws {
        let date = try #require(LocalDate(iso: "2026-09-26"))
        #expect(date.year == 2026 && date.month == 9 && date.day == 26)
        #expect(date.iso == "2026-09-26")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "2026-9-1", "26-09-01", "2026/09/01", ""])
    func rejectsInvalid(_ text: String) {
        #expect(LocalDate(iso: text) == nil)
    }

    @Test func lateNightStaysOnTheLocalDay() throws {
        // 23:30 in Los Angeles on Sep 26 is already Sep 27 in UTC.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-27T06:30:00Z"))
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(LocalDate(instant, in: la).iso == "2026-09-26")
        #expect(LocalDate(instant, in: TimeZone(identifier: "UTC")!).iso == "2026-09-27")
    }

    @Test func arithmeticCrossesMonthYearLeapAndDST() throws {
        #expect(LocalDate(iso: "2026-12-31")!.adding(days: 1).iso == "2027-01-01")
        #expect(LocalDate(iso: "2028-02-28")!.adding(days: 1).iso == "2028-02-29")
        #expect(LocalDate(iso: "2026-11-01")!.adding(days: 1).iso == "2026-11-02") // US DST ends
        #expect(LocalDate(iso: "2026-03-08")!.adding(days: -1).iso == "2026-03-07") // US DST starts
        #expect(LocalDate(iso: "2026-09-26")!.adding(days: -14).iso == "2026-09-12")
    }

    @Test func daysBetweenAndRange() {
        let a = LocalDate(iso: "2026-09-20")!, b = LocalDate(iso: "2026-09-26")!
        #expect(a.days(until: b) == 6)
        #expect(b.days(until: a) == -6)
        #expect(LocalDate.range(from: a, through: b).map(\.iso).first == "2026-09-20")
        #expect(LocalDate.range(from: a, through: b).count == 7)
        #expect(LocalDate.range(from: b, through: a).isEmpty)
    }

    @Test func ordersChronologically() {
        #expect(LocalDate(iso: "2026-09-30")! < LocalDate(iso: "2026-10-01")!)
    }

    @Test func codesAsPlainString() throws {
        let data = try JSONEncoder().encode([LocalDate(iso: "2026-09-26")!])
        #expect(String(data: data, encoding: .utf8) == #"["2026-09-26"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data).first?.iso == "2026-09-26")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDate].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
    }
}
