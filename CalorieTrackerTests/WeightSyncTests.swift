import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

struct WeightImportTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let day = LocalDate(iso: iso)!
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                  hour: hour, minute: minute))!
    }

    @Test func latestReadingOfTheDayWins() {
        let samples = [
            WeightSample(taken: at("2026-09-20", 7), pounds: 172.0),
            WeightSample(taken: at("2026-09-20", 21), pounds: 173.4),
            WeightSample(taken: at("2026-09-20", 12), pounds: 172.6),
        ]
        #expect(WeightImport.dailyLatest(samples, in: newYork) == [LocalDate(iso: "2026-09-20")!: 173.4])
    }

    @Test func lateNightReadingStaysOnItsLocalDay() {
        // 23:30 in New York is already the next day in UTC.
        let samples = [WeightSample(taken: at("2026-09-20", 23, 30), pounds: 171.0)]
        #expect(WeightImport.dailyLatest(samples, in: newYork).keys.first == LocalDate(iso: "2026-09-20"))
    }

    @Test func roundsToOneDecimal() {
        let samples = [WeightSample(taken: at("2026-09-20", 7), pounds: 77.5 * 2.20462262)]
        #expect(WeightImport.dailyLatest(samples, in: newYork).values.first == 170.9)
    }

    @Test func windowCountsTodayAsDayOne() {
        let today = LocalDate(iso: "2026-10-02")!
        #expect(WeightImport.windowStart(today: today).days(until: today) == WeightImport.windowDays - 1)
    }
}

@MainActor
struct WeightSyncTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let today = LocalDate(iso: "2026-10-02")!
    var start: LocalDate { WeightImport.windowStart(today: today) }

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    func day(_ back: Int) -> LocalDate { today.adding(days: -back) }
    func rows() throws -> [DailySummary] { try context.fetch(FetchDescriptor<DailySummary>()) }

    @Test func writesToTheReadingsOwnDate() throws {
        try WeightSync.apply([day(3): 172.4], from: start, through: today, in: context)
        let row = try #require(try DailySummaryStore.find(day(3), in: context))
        #expect(row.weight == 172.4)
        #expect(row.weightFromHealth)
        #expect(try DailySummaryStore.find(today, in: context) == nil)
    }

    @Test func fillsAnExistingRowWithoutDuplicating() throws {
        let existing = try DailySummaryStore.getOrCreate(day(3), in: context)
        existing.calories = 1900
        existing.rolledUp = true
        try context.save()

        try WeightSync.apply([day(3): 172.4], from: start, through: today, in: context)
        #expect(try rows().count == 1)
        #expect(existing.weight == 172.4)
        #expect(existing.calories == 1900)
    }

    @Test func secondRunWithSameDataChangesNothing() throws {
        let daily = [day(1): 171.0, day(2): 171.6]
        #expect(try WeightSync.apply(daily, from: start, through: today, in: context) == 2)
        #expect(try WeightSync.apply(daily, from: start, through: today, in: context) == 0)
    }

    @Test func correctionInHealthIsFollowed() throws {
        try WeightSync.apply([day(1): 171.0], from: start, through: today, in: context)
        try WeightSync.apply([day(1): 170.2], from: start, through: today, in: context)
        #expect(try DailySummaryStore.find(day(1), in: context)?.weight == 170.2)
    }

    @Test func readingDeletedInHealthIsCleared() throws {
        try WeightSync.apply([day(1): 171.0, day(2): 171.6], from: start, through: today, in: context)
        try WeightSync.apply([day(2): 171.6], from: start, through: today, in: context)
        let row = try #require(try DailySummaryStore.find(day(1), in: context))
        #expect(row.weight == nil)
        #expect(!row.weightFromHealth)
    }

    @Test func weightsNotFromHealthAreLeftAlone() throws {
        let other = try DailySummaryStore.getOrCreate(day(4), in: context)
        other.weight = 175.0
        try context.save()
        try WeightSync.apply([:], from: start, through: today, in: context)
        #expect(other.weight == 175.0)
    }

    @Test func historyOlderThanTheWindowIsLeftAlone() throws {
        let old = day(WeightImport.windowDays + 10)
        try WeightSync.apply([old: 180.0], from: old, through: today, in: context)
        try WeightSync.apply([:], from: start, through: today, in: context)
        #expect(try DailySummaryStore.find(old, in: context)?.weight == 180.0)
    }

    @Test func readingsOutsideTheWindowAreIgnored() throws {
        try WeightSync.apply([day(WeightImport.windowDays): 180.0, today.adding(days: 1): 170.0],
                             from: start, through: today, in: context)
        #expect(try rows().isEmpty)
    }
}

struct WeightEntryTests {
    @Test func readsEitherDecimalMark() {
        #expect(WeightEntry.value(from: "172.4", unit: .lb) == 172.4)
        #expect(WeightEntry.value(from: " 78,2 ", unit: .kg) == 78.2)
    }

    @Test func rejectsTyposAndNonsense() {
        #expect(WeightEntry.value(from: "", unit: .lb) == nil)
        #expect(WeightEntry.value(from: "17.24.1", unit: .lb) == nil)
        #expect(WeightEntry.value(from: "1724", unit: .lb) == nil)
        #expect(WeightEntry.value(from: "17", unit: .lb) == nil)
    }

    @Test func plausibilityIsCheckedInPounds() {
        // The limit is 700 lb: 300 kg (661 lb) passes, 320 kg (705 lb) doesn't.
        #expect(WeightEntry.value(from: "300", unit: .lb) == 300)
        #expect(WeightEntry.value(from: "300", unit: .kg) == 300)
        #expect(WeightEntry.value(from: "320", unit: .kg) == nil)
    }
}
