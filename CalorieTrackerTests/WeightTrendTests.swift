import Foundation
import Testing
@testable import CalorieTracker

struct WeightTrendTests {
    let today = LocalDate(iso: "2026-10-02")!

    func reading(_ back: Int, _ pounds: Double) -> WeightReading {
        WeightReading(day: today.adding(days: -back), pounds: pounds)
    }

    @Test func spanStartsAtTheFirstLoggedDaySoGapsShow() {
        let series = WeightSeries(readings: [reading(3, 170)], firstLoggingDay: today.adding(days: -10), today: today)
        #expect(series.span.first == today.adding(days: -10))
        #expect(series.span.last == today)
        #expect(series.span.count == 11)
    }

    @Test func averageNeedsFourReadingsInTheTrailingWeek() {
        // Three readings in a week: no line at all.
        let sparse = WeightSeries(readings: [reading(6, 170), reading(4, 171), reading(1, 172)],
                                  firstLoggingDay: nil, today: today)
        #expect(sparse.averageRuns.isEmpty)
        #expect(!sparse.hasTrend)

        // Four readings: the average starts on the day the fourth arrives.
        let enough = WeightSeries(readings: [reading(6, 170), reading(4, 171), reading(2, 172), reading(1, 171)],
                                  firstLoggingDay: nil, today: today)
        #expect(enough.average(on: today.adding(days: -1)) == 171)
        #expect(enough.average(on: today.adding(days: -2)) == nil)
        #expect(enough.hasTrend) // yesterday and today both qualify
    }

    @Test func aGapSplitsTheAverageIntoSeparateRuns() {
        // Daily readings for 10 days, nothing for 8, then daily again for 10.
        let early = (19...28).map { reading($0, 175) }
        let late = (0...9).map { reading($0, 172) }
        let series = WeightSeries(readings: early + late, firstLoggingDay: nil, today: today)
        #expect(series.averageRuns.count == 2)
        #expect(series.average(on: today.adding(days: -14)) == nil) // inside the gap
    }

    @Test func changeIsLatestMinusFirst() {
        let series = WeightSeries(readings: [reading(9, 172.4), reading(0, 170.1)], firstLoggingDay: nil, today: today)
        #expect(series.change == -2.3)
        #expect(series.latest?.pounds == 170.1)
    }

    @Test func trendUnlocksAfterThreeWeeksOfBoth() {
        #expect(!TrendGate(intakeDays: 20, readings: 30).isUnlocked)
        #expect(!TrendGate(intakeDays: 30, readings: 11).isUnlocked)
        #expect(TrendGate(intakeDays: 21, readings: 12).isUnlocked)
    }

    @Test func lockedProgressLinesNeverShowMoreThanNeeded() {
        let short = TrendGate(intakeDays: 2, readings: 16)
        #expect(short.intakeLine == "Intake: 2 of 21 days logged")
        #expect(short.weightLine == "Weight: ✓ 16 readings — enough")
        let noWeight = TrendGate(intakeDays: 25, readings: 3)
        #expect(noWeight.intakeLine == "Intake: ✓ 25 days logged — enough")
        #expect(noWeight.weightLine == "Weight: 3 of 12 readings")
    }

    @Test func energyBalanceFromIntakeAndTheWeightTrend() throws {
        // A steady 1 lb a week down (0.5 lb every 3.5 days, read daily), eating 1,800 a day
        // with two days unlogged.
        let readings = (0...27).map { reading($0, 170 + Double($0) / 7) }
        var totals: [LocalDate: NutritionTotals] = [:]
        for back in 1...27 where back != 5 && back != 12 {
            totals[today.adding(days: -back)] = NutritionTotals(calories: 1800, entryCount: 3)
        }
        let series = WeightSeries(readings: readings, firstLoggingDay: nil, today: today)
        let balance = try #require(EnergyBalance(series: series, dayTotals: totals, today: today))
        #expect(balance.through == today.adding(days: -1)) // today is left out
        #expect(balance.averageIntake == 1800) // gaps aren't averaged over
        #expect(balance.poundsChange < 0)
        #expect(balance.impliedDailyBalance == -500) // 1 lb a week ≈ 500 kcal a day
        #expect(balance.estimatedMaintenance == 2300)
    }

    @Test func noEnergyBalanceOnAShortStretch() {
        let readings = (0...10).map { reading($0, 170) }
        let totals = [today.adding(days: -1): NutritionTotals(calories: 1800, entryCount: 3)]
        let series = WeightSeries(readings: readings, firstLoggingDay: nil, today: today)
        #expect(EnergyBalance(series: series, dayTotals: totals, today: today) == nil)
    }
}
