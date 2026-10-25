import Foundation
import Testing
@testable import CalorieTracker

struct StatsTests {
    let today = LocalDate(iso: "2026-09-26")!

    @Test func totalsSumAndTrackEstimates() {
        let t = NutritionTotals([
            EntryDraft(date: today, meal: .breakfast, description: "a", calories: 300, protein: 10, carbs: 20, fat: 5, source: .label),
            EntryDraft(date: today, meal: .lunch, description: "b", calories: 500, protein: 20, carbs: 40, fat: 10, source: .estimate),
            EntryDraft(date: today, meal: .dinner, description: "c", calories: 200, protein: 5, carbs: 10, fat: 15, source: .photoEstimate),
        ])
        #expect(t == NutritionTotals(calories: 1000, protein: 35, carbs: 70, fat: 30, estimatedCalories: 700, entryCount: 3))
        #expect(t.estimatedPercent == 70)
        #expect(NutritionTotals.zero.estimatedPercent == nil)
    }

    @Test func remainingGoesNegativeWhenOver() {
        let r = Remaining(targets: .defaults, eaten: NutritionTotals(calories: 1900, protein: 100, carbs: 170, fat: 50))
        #expect(r.calories == -115)
        #expect(r.isOverCalories)
        #expect(r.protein == 45 && r.carbs == -5 && r.fat == 10)
    }

    @Test func roundsToNearestFive() {
        #expect(Rounding.nearest5(1792.5) == 1795)
        #expect(Rounding.nearest5(1792.4) == 1790)
        #expect(Rounding.nearest5(0) == 0)
    }

    /// Issue #46: this used to trap on a non-finite or huge value.
    @Test func roundingNeverTraps() {
        #expect(Rounding.nearest5(.infinity) == 0)
        #expect(Rounding.nearest5(-.infinity) == 0)
        #expect(Rounding.nearest5(.nan) == 0)
        #expect(Rounding.nearest5(2.5e19) > 4_000_000_000_000_000_000)
        #expect(Rounding.nearest5(-2.5e19) < -4_000_000_000_000_000_000)
        #expect(Rounding.nearest5(-12.5) == -15)
    }

    @Test func targetHistoryJudgesEachDayByItsOwnTargets() {
        let old = MacroTargets(calories: 2000, protein: 120, carbs: 200, fat: 70)
        let periods = [TargetPeriod(effectiveFrom: LocalDate(iso: "2026-09-24")!, targets: .defaults),
                       TargetPeriod(effectiveFrom: LocalDate(iso: "2026-09-01")!, targets: old)]
        #expect(TargetHistory.effective(on: LocalDate(iso: "2026-09-23")!, in: periods) == old)
        #expect(TargetHistory.effective(on: LocalDate(iso: "2026-09-24")!, in: periods) == .defaults)
        #expect(TargetHistory.effective(on: LocalDate(iso: "2026-08-01")!, in: periods) == old)
        #expect(TargetHistory.effective(on: today, in: []) == .defaults)
    }

    @Test func weekExcludesTodayAndGaps() {
        let days: [LocalDate: NutritionTotals] = [
            today.adding(days: -1): NutritionTotals(calories: 1800, protein: 100, carbs: 150, fat: 60, estimatedCalories: 900, entryCount: 3),
            today.adding(days: -2): NutritionTotals(calories: 2000, protein: 80, carbs: 200, fat: 80, estimatedCalories: 2000, entryCount: 4),
            today.adding(days: -4): NutritionTotals(calories: 1600, protein: 90, carbs: 140, fat: 50, estimatedCalories: 0, entryCount: 2),
            today: NutritionTotals(calories: 5000, protein: 1, carbs: 1, fat: 1, estimatedCalories: 5000, entryCount: 1),
        ]
        let stats = WeekStats(today: today, dayTotals: days, targetPeriods: [])
        #expect(stats.days.count == 7)
        #expect(stats.days.first?.iso == "2026-09-20")
        #expect(stats.completeDays.count == 3)
        #expect(stats.missingDays.count == 3)
        #expect(!stats.completeDays.contains(today) && !stats.missingDays.contains(today))
        #expect(stats.averageCalories == 1800) // (1800 + 2000 + 1600) / 3, not / 6
        #expect(stats.averageProtein == 90)
        #expect(stats.daysOverTarget == 2) // 1800 and 2000 are over 1785
        #expect(stats.estimatedPercent == 54) // 2900 / 5400
    }

    @Test func weekJudgesOverAgainstTargetsInForceThatDay() {
        let days: [LocalDate: NutritionTotals] = [
            today.adding(days: -3): NutritionTotals(calories: 1900, entryCount: 1),
            today.adding(days: -1): NutritionTotals(calories: 1900, entryCount: 1),
        ]
        let periods = [TargetPeriod(effectiveFrom: today.adding(days: -30),
                                    targets: MacroTargets(calories: 2000, protein: 1, carbs: 1, fat: 1)),
                       TargetPeriod(effectiveFrom: today.adding(days: -2), targets: .defaults)]
        #expect(WeekStats(today: today, dayTotals: days, targetPeriods: periods).daysOverTarget == 1)
    }

    @Test func emptyWeekHasNoAverages() {
        let stats = WeekStats(today: today, dayTotals: [:], targetPeriods: [])
        #expect(stats.averageCalories == nil)
        #expect(stats.estimatedPercent == nil)
        #expect(stats.missingDays.count == 6)
    }

    @Test func syntheticWeekStats() {
        var days: [LocalDate: NutritionTotals] = [:]
        for (day, group) in Dictionary(grouping: SyntheticWeek.entries, by: \.date) {
            days[day] = NutritionTotals(group)
        }
        let stats = WeekStats(today: SyntheticWeek.today, dayTotals: days, targetPeriods: [],
                              firstLoggingDay: SyntheticWeek.firstDay)
        #expect(stats.completeDays.count == 5) // Sep 20–25 minus the gap; Sep 19 falls outside the window
        #expect(stats.missingDays == [SyntheticWeek.gapDay])
        #expect(!stats.includesFirstLoggingDay)

        let complete = SyntheticWeek.entries.filter { stats.completeDays.contains($0.date) }
        let sum = NutritionTotals(complete)
        #expect(stats.averageCalories == Rounding.nearest5(Double(sum.calories) / 5))
        #expect(stats.estimatedPercent == sum.estimatedPercent)
        #expect((50...85).contains(stats.estimatedPercent ?? 0)) // estimates dominate, as in the pilot
    }

    @Test func earlierWeekCountsAllSevenDays() {
        let end = today.adding(days: -7)
        let days: [LocalDate: NutritionTotals] = [
            end: NutritionTotals(calories: 1700, entryCount: 3),
            end.adding(days: -6): NutritionTotals(calories: 1900, entryCount: 3),
            today: NutritionTotals(calories: 900, entryCount: 1), // outside this window
        ]
        let stats = WeekStats(today: today, ending: end, dayTotals: days, targetPeriods: [])
        #expect(stats.days.first == end.adding(days: -6) && stats.days.last == end)
        #expect(!stats.includesToday)
        #expect(stats.completeDays.count == 2)
        #expect(stats.missingDays.count == 5)
        #expect(stats.averageCalories == 1800)
    }

    @Test func honestyNoteSaysWhatIsLeftOut() {
        let days: [LocalDate: NutritionTotals] = [
            today.adding(days: -1): NutritionTotals(calories: 1800, entryCount: 3),
            today.adding(days: -3): NutritionTotals(calories: 1800, entryCount: 3),
        ]
        let stats = WeekStats(today: today, dayTotals: days, targetPeriods: [],
                              firstLoggingDay: today.adding(days: -3))
        let note = stats.honestyNote(text: LogText(locale: Locale(identifier: "en_US")))
        #expect(note == "Averages cover 2 complete days, Sep 23 to Sep 25. Today is left out because it isn't finished. 4 days had no data and aren't averaged over. Sep 23 was the first day of logging and may be incomplete. Solid bars are from labels; hatched bars are estimates.")
    }
}
