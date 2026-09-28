import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

@MainActor
struct StoreTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    func loadSyntheticWeek(shuffled: Bool = false) throws {
        let pending = SyntheticWeek.entries.map { PendingEntry(draft: $0, origin: SyntheticWeek.origin(for: $0)) }
        try EntryWriter.commit(shuffled ? pending.reversed() : pending, confirmedByUser: true, in: context)
    }

    // MARK: DailySummary get-or-create

    @Test func getOrCreateNeverDuplicates() throws {
        let day = SyntheticWeek.today
        let first = try DailySummaryStore.getOrCreate(day, in: context)
        first.weight = 171.6
        let second = try DailySummaryStore.getOrCreate(day, in: context)
        try context.save()
        #expect(first === second)
        #expect(try count(DailySummary.self) == 1)
        #expect(try DailySummaryStore.find(day, in: context)?.weight == 171.6)
    }

    @Test func missingRowIsNotAssumed() throws {
        #expect(try DailySummaryStore.find(SyntheticWeek.gapDay, in: context) == nil)
    }

    // MARK: Write boundary

    @Test func validBatchIsWrittenTogether() throws {
        try loadSyntheticWeek()
        #expect(try count(MealEntry.self) == SyntheticWeek.entries.count)
    }

    @Test func oneBadEntryRejectsTheWholeBatch() throws {
        let good = SyntheticWeek.entries[2]
        var bad = good
        bad.fat = 55 // macros no longer add up
        let batch = [PendingEntry(draft: good, origin: .statedNumbers),
                     PendingEntry(draft: bad, origin: .statedNumbers)]
        #expect(throws: WriteRejected.self) {
            try EntryWriter.commit(batch, confirmedByUser: false, in: context)
        }
        do {
            try EntryWriter.commit(batch, confirmedByUser: false, in: context)
        } catch let rejected as WriteRejected {
            #expect(rejected.issues.keys.sorted() == [1])
        }
        #expect(try count(MealEntry.self) == 0)
    }

    @Test func unconfirmedEstimateIsNotWritten() throws {
        let estimate = SyntheticWeek.entries[0]
        #expect(throws: WriteRejected(issues: [0: [.needsConfirmation]])) {
            try EntryWriter.commit([PendingEntry(draft: estimate, origin: .description)],
                                   confirmedByUser: false, in: context)
        }
        #expect(try count(MealEntry.self) == 0)
    }

    // MARK: Roll-up

    @Test func rollUpPreservesTotalsAndDeletesDetail() throws {
        try loadSyntheticWeek(shuffled: true)
        let span = (SyntheticWeek.firstDay, SyntheticWeek.today)
        let before = try DayTotalsIndex.load(from: span.0, through: span.1, in: context)

        // On Oct 10 with a 14-day window, Sep 25 and older roll up; Sep 26 stays as detail.
        let today = LocalDate(iso: "2026-10-10")!
        let result = try RollUp.run(in: context, today: today, detailWindowDays: 14)

        #expect(result.daysRolled.map(\.iso) == ["2026-09-19", "2026-09-20", "2026-09-21",
                                                  "2026-09-22", "2026-09-24", "2026-09-25"])
        #expect(result.entriesDeleted == SyntheticWeek.entries.count - 2)
        #expect(try count(MealEntry.self) == 2)
        #expect(try count(DailySummary.self) == 6) // no row invented for the gap day
        #expect(try DayTotalsIndex.load(from: span.0, through: span.1, in: context) == before)
    }

    @Test func mealsDetailIsInMealOrderWithSource() throws {
        try loadSyntheticWeek(shuffled: true)
        try RollUp.run(in: context, today: LocalDate(iso: "2026-10-10")!, detailWindowDays: 14)
        let row = try #require(try DailySummaryStore.find(LocalDate(iso: "2026-09-20")!, in: context))
        let meals = row.mealsDetail.split(separator: "\n").map { String($0.split(separator: " ").first!) }
        #expect(meals == ["Breakfast", "Lunch", "Dinner", "Dinner", "Snack"])
        #expect(row.mealsDetail.hasPrefix("Breakfast — Yogurt with granola (345 cal, 17p/26c/19f) [Label]"))
        #expect(row.mealsDetail.contains("Glass of red wine (125 cal, 0p/4c/0f) [Estimate] [Alcohol]"))
    }

    @Test func rollUpKeepsAnExistingWeightRow() throws {
        try loadSyntheticWeek()
        let day = LocalDate(iso: "2026-09-20")!
        try DailySummaryStore.getOrCreate(day, in: context).weight = 172.4
        try context.save()

        try RollUp.run(in: context, today: LocalDate(iso: "2026-10-10")!, detailWindowDays: 14)
        let rows = try context.fetch(FetchDescriptor<DailySummary>()).filter { $0.dayKey == day.iso }
        #expect(rows.count == 1)
        #expect(rows.first?.weight == 172.4)
        #expect(rows.first?.rolledUp == true)
        #expect(rows.first?.entryCount == 5)
    }

    @Test func weightOnlyRowCountsAsNoData() throws {
        try DailySummaryStore.getOrCreate(SyntheticWeek.gapDay, in: context).weight = 171.8
        try context.save()
        let totals = try DayTotalsIndex.load(from: SyntheticWeek.gapDay, through: SyntheticWeek.gapDay, in: context)
        #expect(totals[SyntheticWeek.gapDay] == nil)
    }

    @Test func rollUpIsIdempotent() throws {
        try loadSyntheticWeek()
        let today = LocalDate(iso: "2026-10-10")!
        try RollUp.run(in: context, today: today, detailWindowDays: 14)
        let again = try RollUp.run(in: context, today: today, detailWindowDays: 14)
        #expect(again == RollUp.Result())
    }

    @Test func windowBoundary() throws {
        try loadSyntheticWeek()
        // On Oct 9, the 14-day cutoff is Sep 25: Sep 25 is kept, Sep 24 and older roll up.
        let result = try RollUp.run(in: context, today: LocalDate(iso: "2026-10-09")!, detailWindowDays: 14)
        #expect(result.daysRolled.last?.iso == "2026-09-24")
        let kept = try context.fetch(FetchDescriptor<MealEntry>()).map(\.dayKey)
        #expect(Set(kept) == ["2026-09-25", "2026-09-26"])
    }

    @Test func backDatedEntryAddsToARolledUpDay() throws {
        try loadSyntheticWeek()
        let today = LocalDate(iso: "2026-10-10")!
        try RollUp.run(in: context, today: today, detailWindowDays: 14)
        let day = LocalDate(iso: "2026-09-21")!
        let before = try #require(try DailySummaryStore.find(day, in: context)).totals

        let late = EntryDraft(date: day, meal: .snack, description: "Forgotten banana",
                              calories: 105, protein: 1, carbs: 27, fat: 0, source: .estimate)
        try EntryWriter.commit([PendingEntry(draft: late, origin: .description)], confirmedByUser: true, in: context)
        try RollUp.run(in: context, today: today, detailWindowDays: 14)

        let row = try #require(try DailySummaryStore.find(day, in: context))
        #expect(row.totals == before + NutritionTotals([late]))
        #expect(row.mealsDetail.hasSuffix("Snack — Forgotten banana (105 cal, 1p/27c/0f) [Estimate]"))
        #expect(try count(DailySummary.self) == 6)
    }

    // MARK: Targets

    @Test func storedTargetsHistory() throws {
        context.insert(Targets(effectiveFrom: LocalDate(iso: "2026-09-01")!,
                               targets: MacroTargets(calories: 2000, protein: 120, carbs: 200, fat: 70)))
        context.insert(Targets(effectiveFrom: LocalDate(iso: "2026-09-24")!, targets: .defaults, goalNote: "lose ~1 lb/week"))
        try context.save()
        #expect(try TargetStore.current(on: LocalDate(iso: "2026-09-23")!, in: context).calories == 2000)
        #expect(try TargetStore.current(on: SyntheticWeek.today, in: context) == .defaults)
    }

    // MARK: Usual meals

    @Test func usualMealLogsWithItsStoredSource() throws {
        let usual = UsualMeal(name: "Usual breakfast", triggerPhrases: ["the usual"], meal: .breakfast,
                              description: "Yogurt with granola", calories: 345, protein: 17, carbs: 26, fat: 19,
                              source: .estimate)
        context.insert(usual)
        let draft = usual.draft(on: SyntheticWeek.today)
        try EntryWriter.commit([PendingEntry(draft: draft, origin: .usualMeal(storedSource: usual.source))],
                               confirmedByUser: false, in: context)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).first?.source == .estimate)
    }
}
