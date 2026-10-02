import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

@MainActor
struct UsualMealStoreTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    @discardableResult
    func add(_ name: String, phrases: [String] = [], source: Source = .label) throws -> UsualMeal {
        let usual = UsualMeal(name: name, triggerPhrases: phrases, meal: .breakfast, description: "Oats with milk",
                              calories: 350, protein: 15, carbs: 55, fat: 8, source: source)
        context.insert(usual)
        try context.save()
        return usual
    }

    @Test func savesAnEdit() throws {
        let oats = try add("usual breakfast")
        var edit = UsualMealStore.Edit(oats)
        edit.name = "  oats  "
        edit.triggerPhrases = UsualMealStore.phrases(from: "my oats, , the usual ")
        edit.calories = 400
        edit.carbs = 67
        try UsualMealStore.update(oats, with: edit, in: context)
        #expect(oats.name == "oats")
        #expect(oats.triggerPhrases == ["my oats", "the usual"])
        #expect(oats.calories == 400)
    }

    @Test func sourceNeverChanges() throws {
        let estimate = try add("usual lunch", source: .estimate)
        var edit = UsualMealStore.Edit(estimate)
        edit.calories = 360
        try UsualMealStore.update(estimate, with: edit, in: context)
        #expect(estimate.source == .estimate)
    }

    @Test func rejectsAnEmptyName() throws {
        let oats = try add("usual breakfast")
        var edit = UsualMealStore.Edit(oats)
        edit.name = "   "
        #expect(throws: UsualMealStore.Problem.emptyName) { try UsualMealStore.update(oats, with: edit, in: context) }
    }

    @Test func rejectsANameAnotherMealAnswersTo() throws {
        try add("usual lunch", phrases: ["my normal lunch"])
        let oats = try add("usual breakfast")
        var edit = UsualMealStore.Edit(oats)
        edit.triggerPhrases = ["My Normal Lunch!"]
        #expect(throws: UsualMealStore.Problem.nameTaken("My Normal Lunch!")) {
            try UsualMealStore.update(oats, with: edit, in: context)
        }
        #expect(oats.triggerPhrases.isEmpty)
    }

    @Test func keepingItsOwnNameIsFine() throws {
        let oats = try add("usual breakfast", phrases: ["oats"])
        var edit = UsualMealStore.Edit(oats)
        edit.description = "Oats with oat milk"
        try UsualMealStore.update(oats, with: edit, in: context)
        #expect(oats.foodDescription == "Oats with oat milk")
    }

    @Test func macrosMustStillAddUp() throws {
        let oats = try add("usual breakfast")
        var edit = UsualMealStore.Edit(oats)
        edit.calories = 900
        #expect(throws: UsualMealStore.Problem.self) { try UsualMealStore.update(oats, with: edit, in: context) }
        #expect(oats.calories == 350)
    }

    @Test func editingDoesNotRewriteLoggedEntries() throws {
        let oats = try add("usual breakfast")
        try EntryWriter.commit([PendingEntry(draft: oats.draft(on: LocalDate(iso: "2026-10-01")!),
                                             origin: .usualMeal(storedSource: .label))],
                               confirmedByUser: false, in: context)
        var edit = UsualMealStore.Edit(oats)
        edit.calories = 400
        edit.carbs = 67
        try UsualMealStore.update(oats, with: edit, in: context)
        try UsualMealStore.delete(oats, in: context)
        let logged = try context.fetch(FetchDescriptor<MealEntry>())
        #expect(logged.map(\.calories) == [350])
        #expect(try context.fetchCount(FetchDescriptor<UsualMeal>()) == 0)
    }
}
