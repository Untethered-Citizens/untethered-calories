import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

/// Upper limits on entries, usual meals and targets (#42). Before them, a model-sent number
/// such as 5e18 kcal was stored, then trapped Int arithmetic every time the day was added up.
@MainActor
struct NumberLimitsTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let today = LocalDate(iso: "2026-09-29")!

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    func draft(cal: Int, p: Int = 0, c: Int = 0, f: Int = 0, alcohol: Bool = false) -> EntryDraft {
        EntryDraft(date: today, meal: .snack, description: "Food", calories: cal,
                   protein: p, carbs: c, fat: f, source: .label, containsAlcohol: alcohol)
    }

    func run(_ name: String, _ json: String) throws -> ToolOutcome {
        let runner = ToolRunner(context: context, today: today, conversationHasPhoto: false)
        return runner.run(ToolCall(id: "t", name: name,
                                   input: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
    }

    // MARK: The limits themselves

    @Test func limitsAreInclusive() {
        #expect(Integrity.sizeIssues(calories: 20_000, protein: 5_000, carbs: 5_000, fat: 5_000).isEmpty)
        #expect(Integrity.sizeIssues(calories: 20_001, protein: 0, carbs: 5_001, fat: 0)
                == [.tooLarge(field: "calories", limit: 20_000), .tooLarge(field: "carbs", limit: 5_000)])
    }

    @Test func macroArithmeticSaturatesInsteadOfTrapping() {
        #expect(Integrity.macroCalories(protein: .max / 2, carbs: 0, fat: 0) == .max)
        #expect(Integrity.macroCalories(protein: 0, carbs: 0, fat: .min / 2) == .min)
        #expect(Integrity.macroIssue(draft(cal: 5, p: .max / 2)) != nil)
    }

    @Test func weekChartScaleClampsInsteadOfTrapping() {
        #expect(WeekChart.scaleTop(target: 7_000_000_000_000_000_000, highest: 0) == .max)
        #expect(WeekChart.scaleTop(target: 0, highest: .max) == .max)
    }

    // MARK: Entries

    @Test func writeBoundaryRefusesHugeEntriesEvenWithAlcohol() throws {
        let huge = PendingEntry(draft: draft(cal: 5_000_000_000_000_000_000, alcohol: true), origin: .statedNumbers)
        let refused: [IntegrityIssue] = [.tooLarge(field: "calories", limit: 20_000)]
        #expect(throws: WriteRejected(issues: [0: refused, 1: refused])) {
            try EntryWriter.commit([huge, huge], confirmedByUser: false, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    /// The audit's exact path: two 5e18 kcal entries on one day through log_entries.
    @Test func modelSentHugeNumbersAreRefusedWithNothingStored() throws {
        let item = #"{"date":"2026-09-29","meal":"Snack","description":"x","calories":5000000000000000000,"protein":0,"carbs":0,"fat":0,"source":"Label","contains_alcohol":true,"basis":"stated_numbers","usual_meal_name":""}"#
        let outcome = try run("log_entries", #"{"entries":[\#(item),\#(item)]}"#)
        #expect(outcome.isError)
        #expect(outcome.text.contains("calories is above the app's limit of 20000 per entry"))
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    @Test func aBigRealMealStillLogs() throws {
        // A whole large pizza: 4·110 + 4·280 + 9·105 = 2,505.
        let item = #"{"date":"2026-09-29","meal":"Dinner","description":"Large pizza","calories":2500,"protein":110,"carbs":280,"fat":105,"source":"Label","contains_alcohol":false,"basis":"stated_numbers","usual_meal_name":""}"#
        let outcome = try run("log_entries", #"{"entries":[\#(item)]}"#)
        #expect(!outcome.isError)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).count == 1)
    }

    @Test func correctionsAreLimitedToo() throws {
        let saved = try EntryWriter.commit([PendingEntry(draft: draft(cal: 400, c: 100), origin: .statedNumbers)],
                                           confirmedByUser: false, in: context)[0]
        #expect(throws: WriteRejected.self) { try EntryWriter.update(saved, to: draft(cal: 30_000, c: 7_500), in: context) }
        #expect(saved.calories == 400)
    }

    @Test func refusalIsExplainedInPlainWords() {
        let rejected = WriteRejected(issues: [0: [.tooLarge(field: "calories", limit: 20_000)]])
        let text = EntryEditView.explain(rejected, drafts: [draft(cal: 30_000)], saveTitle: "Log")
        #expect(text.contains("This entry: calories can be at most 20,000 cal."))
    }

    // MARK: Usual meals

    @Test func hugeUsualMealGetsNoCard() throws {
        let json = #"{"name":"Big","trigger_phrases":[],"meal":"Lunch","description":"x","calories":5000000000000000000,"protein":0,"carbs":0,"fat":0,"source":"Label","contains_alcohol":true}"#
        let outcome = try run("add_usual_meal", json)
        #expect(outcome.isError)
        #expect(outcome.text.contains("at most 20000 kcal"))
    }

    @Test func usualMealEditsAreLimited() throws {
        let oats = UsualMeal(name: "oats", triggerPhrases: [], meal: .breakfast, description: "Oats",
                             calories: 350, protein: 15, carbs: 55, fat: 8, source: .label)
        context.insert(oats)
        var edit = UsualMealStore.Edit(oats)
        edit.carbs = 6_000
        edit.calories = 24_000
        let problem = UsualMealStore.problems(with: edit, for: oats, among: [oats])
        #expect(problem == .integrity([.tooLarge(field: "calories", limit: 20_000), .tooLarge(field: "carbs", limit: 5_000)]))
        #expect(problem?.message == "Calories can be at most 20,000. Carbs can be at most 5,000 g.")
    }

    // MARK: Targets

    @Test func hugeTargetsGetNoCard() throws {
        let json = #"{"calories":7000000000000000000,"protein":3000000000000000000,"carbs":0,"fat":0,"effective_from":"2026-09-29","goal_note":""}"#
        let outcome = try run("propose_targets", json)
        #expect(outcome.isError)
        #expect(outcome.text.contains("at most 20000 kcal"))
    }

    @Test func targetStoreRefusesHugeTargetsFromAnyScreen() throws {
        let huge = MacroTargets(calories: 25_000, protein: 150, carbs: 200, fat: 70)
        #expect(throws: TargetsRejected.self) { try TargetStore.set(huge, from: today, in: context) }
        #expect(try context.fetch(FetchDescriptor<Targets>()).isEmpty)
        let ok = MacroTargets(calories: 20_000, protein: 150, carbs: 200, fat: 70)
        try TargetStore.set(ok, from: today, in: context)
        #expect(try TargetStore.current(on: today, in: context) == ok)
    }
}
