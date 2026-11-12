import Foundation
import Testing
@testable import CalorieTracker

/// Steps in the widget (#16, D95): what it shows when Health can and can't be read.
struct WidgetStepsTests {
    let today = LocalDate(iso: "2026-11-12")!

    @Test func freshReadingWins() {
        let cached = StepsReading(day: today, count: 3_000)
        #expect(StepsShown.pick(fresh: 4_210, cached: cached, today: today, asked: true) == .count(4_210))
    }

    @Test func lockedPhoneShowsTodaysCachedReading() {
        let cached = StepsReading(day: today, count: 3_000)
        #expect(StepsShown.pick(fresh: nil, cached: cached, today: today, asked: true) == .count(3_000))
    }

    @Test func yesterdaysReadingIsNeverShownAsToday() {
        let cached = StepsReading(day: today.adding(days: -1), count: 9_000)
        let shown = StepsShown.pick(fresh: nil, cached: cached, today: today, asked: true)
        #expect(shown == .unknown)
        #expect(shown.number == "–")
        #expect(shown.spoken == "Steps will show when your iPhone is unlocked")
    }

    @Test func notAskedTellsYouToOpenTheApp() {
        let shown = StepsShown.pick(fresh: 500, cached: nil, today: today, asked: false)
        #expect(shown == .notAsked)
        #expect(shown.spoken == "Open Untethered Calories to allow Steps")
        #expect(shown.unit == "tap to allow steps")
        #expect(StepsShown.unknown.unit == "steps")
    }

    @Test func zeroStepsIsARealZero() {
        let shown = StepsShown.pick(fresh: 0, cached: nil, today: today, asked: true)
        #expect(shown == .count(0))
        #expect(shown.number == "0")
    }

    @Test func numbersAreFormattedAndSpokenWithUnits() {
        #expect(StepsShown.count(12_345).number == 12_345.formatted())
        #expect(StepsShown.count(12_345).spoken == "\(12_345.formatted()) steps today")
    }

    @Test func cachedReadingRoundTrips() throws {
        let suite = "WidgetStepsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WidgetShare.readSteps(from: defaults) == nil)
        WidgetShare.writeSteps(StepsReading(day: today, count: 812), to: defaults)
        #expect(WidgetShare.readSteps(from: defaults) == StepsReading(day: today, count: 812))
    }

    @Test func choicesSayWhatTheyInclude() {
        #expect(WidgetShows.calories.includesCalories && !WidgetShows.calories.includesSteps)
        #expect(!WidgetShows.steps.includesCalories && WidgetShows.steps.includesSteps)
        #expect(WidgetShows.both.includesCalories && WidgetShows.both.includesSteps)
        #expect(WidgetChoiceIntent().shows == .calories)
    }
}
