import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

struct CSVExportTests {
    let day = LocalDate(iso: "2026-09-20")!

    @Test func quotesOnlyWhenNeeded() {
        #expect(CSVExport.field("Apple") == "Apple")
        #expect(CSVExport.field("Rice, beans") == "\"Rice, beans\"")
        #expect(CSVExport.field("The \"big\" one") == "\"The \"\"big\"\" one\"")
        #expect(CSVExport.field("a\nb") == "\"a\nb\"")
    }

    @Test func mealRowsUseNamedColumns() {
        let draft = EntryDraft(date: day, meal: .dinner, description: "Wine, red", calories: 125,
                               protein: 0, carbs: 4, fat: 0, source: .label, containsAlcohol: true)
        let lines = CSVExport.meals([draft]).components(separatedBy: "\r\n")
        #expect(lines[0] == "date,meal,food,calories,protein_g,carbs_g,fat_g,source,contains_alcohol")
        #expect(lines[1] == "2026-09-20,Dinner,\"Wine, red\",125,0,4,0,Label,yes")
    }

    @Test func weightOnlyDayLeavesNutritionBlank() {
        let csv = CSVExport.daily([CSVExport.Day(date: day, totals: .zero, weightPounds: 171.04, mealLines: [])], unit: .lb)
        #expect(csv.components(separatedBy: "\r\n")[1] == "2026-09-20,,,,,,,171.0,")
    }

    @Test func weightFollowsTheDisplayUnit() {
        let csv = CSVExport.daily([CSVExport.Day(date: day, totals: .zero, weightPounds: 220.462, mealLines: [])], unit: .kg)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0].contains("weight_kg"))
        #expect(lines[1].contains(",100.0,"))
    }

    @Test func daysAreOldestFirst() {
        let later = CSVExport.Day(date: day.adding(days: 1), totals: .zero, weightPounds: 170, mealLines: [])
        let earlier = CSVExport.Day(date: day, totals: .zero, weightPounds: 171, mealLines: [])
        let lines = CSVExport.daily([later, earlier], unit: .lb).components(separatedBy: "\r\n")
        #expect(lines[1].hasPrefix("2026-09-20"))
        #expect(lines[2].hasPrefix("2026-09-21"))
    }
}

@MainActor
struct RetentionTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let today = LocalDate(iso: "2026-10-02")!

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    func addSummary(daysAgo: Int) throws {
        let row = try DailySummaryStore.getOrCreate(today.adding(days: -daysAgo), in: context)
        row.calories = 1800
        row.entryCount = 4
        row.rolledUp = true
        try context.save()
    }

    @Test func foreverMeansNothingIsDue() throws {
        try addSummary(daysAgo: 1000)
        #expect(try Retention.due(today: today, keepDays: nil, in: context).isEmpty)
    }

    @Test func onlyDaysPastTheLimitAreDue() throws {
        try addSummary(daysAgo: 90)   // exactly at the limit: kept
        try addSummary(daysAgo: 91)
        try addSummary(daysAgo: 200)
        let due = try Retention.due(today: today, keepDays: 90, in: context)
        #expect(due.map(\.dayKey).sorted() == [today.adding(days: -200).iso, today.adding(days: -91).iso])
    }

    @Test func pruneDeletesOnlyDueRows() throws {
        try addSummary(daysAgo: 30)
        try addSummary(daysAgo: 400)
        #expect(try Retention.prune(today: today, keepDays: 365, in: context) == 1)
        #expect(try context.fetchCount(FetchDescriptor<DailySummary>()) == 1)
        #expect(try DailySummaryStore.find(today.adding(days: -30), in: context) != nil)
    }

    @Test func promptComesBackAtMostMonthly() {
        #expect(!Retention.shouldPrompt(dueCount: 0, lastPrompt: nil, today: today))
        #expect(Retention.shouldPrompt(dueCount: 3, lastPrompt: nil, today: today))
        #expect(!Retention.shouldPrompt(dueCount: 3, lastPrompt: today.adding(days: -29), today: today))
        #expect(Retention.shouldPrompt(dueCount: 3, lastPrompt: today.adding(days: -30), today: today))
    }

    @Test func exportCoversDetailAndSummaries() throws {
        try addSummary(daysAgo: 40)
        let pending = SyntheticWeek.entries.prefix(2).map { PendingEntry(draft: $0, origin: SyntheticWeek.origin(for: $0)) }
        try EntryWriter.commit(Array(pending), confirmedByUser: true, in: context)

        let urls = try DataExport.files(from: context, unit: .lb, today: today)
        let daily = try String(contentsOf: urls[0], encoding: .utf8)
        let meals = try String(contentsOf: urls[1], encoding: .utf8)
        #expect(urls.map(\.lastPathComponent) == ["daily.csv", "meals.csv"])
        #expect(meals.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == 3)
        #expect(daily.contains(today.adding(days: -40).iso + ",1800,"))
        #expect(daily.contains(SyntheticWeek.entries[0].date.iso))
    }
}
