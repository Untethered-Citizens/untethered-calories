import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

/// The Home Screen widget's numbers (#5, D93) and its link (D94).
@MainActor
struct WidgetSnapshotTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let today = LocalDate(iso: "2026-11-12")!
    let newYork = TimeZone(identifier: "America/New_York")!

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    func at(_ iso: String, hour: Int, minute: Int = 0, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = LocalDate(iso: iso)!
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                  hour: hour, minute: minute))!
    }

    func snapshot(target: Int = 1_800, eaten: Int = 560, next: Int = 1_800) -> WidgetSnapshot {
        WidgetSnapshot(day: today, timeZoneID: newYork.identifier, target: target, eaten: eaten, nextTarget: next)
    }

    func log(_ calories: Int, on day: LocalDate) throws {
        try EntryWriter.commit([PendingEntry(
            draft: EntryDraft(date: day, meal: .lunch, description: "Food", calories: calories,
                              protein: 0, carbs: calories / 4, fat: 0, source: .label, containsAlcohol: false),
            origin: .statedNumbers)], confirmedByUser: false, in: context)
    }

    // MARK: Building the snapshot

    @Test func snapshotCountsOnlyTodaysFoodAgainstTodaysTarget() throws {
        try TargetStore.set(MacroTargets(calories: 1_800, protein: 140, carbs: 180, fat: 60),
                            from: today.adding(days: -30), in: context)
        try TargetStore.set(MacroTargets(calories: 1_600, protein: 140, carbs: 140, fat: 55),
                            from: today.adding(days: 1), in: context)
        try log(400, on: today)
        try log(160, on: today)
        try log(900, on: today.adding(days: -1)) // back-dated to yesterday: not today's
        let made = try WidgetPublisher.snapshot(today: today, timeZone: newYork, in: context)
        #expect(made == WidgetSnapshot(day: today, timeZoneID: "America/New_York",
                                       target: 1_800, eaten: 560, nextTarget: 1_600))
    }

    @Test func snapshotWithNoFoodIsTheFullTarget() throws {
        let made = try WidgetPublisher.snapshot(today: today, timeZone: newYork, in: context)
        #expect(made.eaten == 0)
        #expect(made.target == MacroTargets.defaults.calories)
    }

    // MARK: What the widget shows

    @Test func sameDayShowsCaloriesLeft() {
        let shown = snapshot().display(at: at("2026-11-12", hour: 23, minute: 59, in: newYork))
        #expect(shown == CaloriesLeft(day: today, left: 1_240))
        #expect(shown.unit == "cal left")
        #expect(!shown.isOver)
    }

    @Test func overTargetShowsHowMuchOver() {
        let shown = snapshot(eaten: 2_012).display(at: at("2026-11-12", hour: 20, in: newYork))
        #expect(shown.isOver)
        #expect(shown.shown == 212)
        #expect(shown.unit == "cal over")
        #expect(shown.spoken == "212 calories over target today")
    }

    @Test func exactlyOnTargetIsZeroLeft() {
        let shown = snapshot(eaten: 1_800).display(at: at("2026-11-12", hour: 20, in: newYork))
        #expect(shown.shown == 0)
        #expect(shown.unit == "cal left")
    }

    @Test func afterMidnightTheNextTargetStartsFresh() {
        let shown = snapshot(next: 1_600).display(at: at("2026-11-13", hour: 0, in: newYork))
        #expect(shown == CaloriesLeft(day: today.adding(days: 1), left: 1_600))
    }

    @Test func daysLaterStillShowTheLatestTargetWithNothingEaten() {
        let shown = snapshot(next: 1_600).display(at: at("2026-11-16", hour: 9, in: newYork))
        #expect(shown == CaloriesLeft(day: LocalDate(iso: "2026-11-16")!, left: 1_600))
    }

    @Test func daysFollowTheSnapshotsTimeZoneNotUTC() {
        // 11 pm in New York is already the 13th in UTC; it's still the 12th for the user.
        let shown = snapshot().display(at: at("2026-11-12", hour: 23, in: newYork))
        #expect(shown.day == today)
    }

    @Test func timelineRedrawsNowAndAtEachLocalMidnight() {
        let now = at("2026-11-12", hour: 15, in: newYork)
        let timeline = snapshot(next: 1_600).timeline(from: now)
        #expect(timeline.map(\.date) == [now, at("2026-11-13", hour: 0, in: newYork),
                                         at("2026-11-14", hour: 0, in: newYork)])
        #expect(timeline.map(\.value.left) == [1_240, 1_600, 1_600])
    }

    @Test func hugeNumbersDontTrap() {
        let shown = snapshot(target: 0, eaten: .max).display(at: at("2026-11-12", hour: 12, in: newYork))
        #expect(shown.isOver)
        #expect(shown.shown > 0)
    }

    // MARK: Sharing

    @Test func writeSkipsUnchangedSnapshots() throws {
        let suite = "WidgetSnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WidgetShare.read(from: defaults) == nil)
        #expect(WidgetShare.write(snapshot(), to: defaults))
        #expect(WidgetShare.read(from: defaults) == snapshot())
        #expect(!WidgetShare.write(snapshot(), to: defaults))
        #expect(WidgetShare.write(snapshot(eaten: 700), to: defaults))
    }

    // MARK: The link

    @Test func onlyTheLogLinkOpensLog() {
        #expect(WidgetLink.opensLog(WidgetLink.log))
        #expect(WidgetLink.opensLog(URL(string: "UntetheredCalories://LOG")!))
        #expect(!WidgetLink.opensLog(URL(string: "untetheredcalories://today")!))
        #expect(!WidgetLink.opensLog(URL(string: "https://log")!))
    }

    @Test func focusRequestIsTakenOnce() {
        let request = ComposerFocusRequest()
        #expect(!request.take())
        request.request()
        #expect(request.take())
        #expect(!request.take())
    }
}
