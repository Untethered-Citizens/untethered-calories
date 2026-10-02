import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

/// Editing and deleting saved entries (D44) goes through the write boundary.
@MainActor
struct EntryCorrectionTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    func saved(_ source: Source = .estimate) throws -> MealEntry {
        let draft = EntryDraft(date: SyntheticWeek.today, meal: .snack, description: "Turkey sandwich",
                               calories: 380, protein: 22, carbs: 38, fat: 14, source: source)
        let origin: EntryOrigin = source == .label ? .statedNumbers : .description
        return try #require(try EntryWriter.commit([PendingEntry(draft: draft, origin: origin)],
                                                   confirmedByUser: true, in: context).first)
    }

    @Test func correctionChangesMealDayAndNumbers() throws {
        let entry = try saved()
        var draft = entry.draft
        draft.meal = .lunch
        draft.date = SyntheticWeek.today.adding(days: -1)
        draft.calories = 420
        draft.carbs = 48
        try EntryWriter.update(entry, to: draft, in: context)

        let stored = try #require(try context.fetch(FetchDescriptor<MealEntry>()).first)
        #expect(stored.meal == .lunch)
        #expect(stored.date == SyntheticWeek.today.adding(days: -1))
        #expect(stored.calories == 420 && stored.carbs == 48)
        #expect(stored.source == .estimate)
    }

    @Test func anEstimateCannotBecomeALabel() throws {
        let entry = try saved(.estimate)
        var draft = entry.draft
        draft.source = .label
        #expect(throws: WriteRejected.self) { try EntryWriter.update(entry, to: draft, in: context) }
        #expect(entry.source == .estimate)
    }

    @Test func aBadCorrectionChangesNothing() throws {
        let entry = try saved(.label)
        var draft = entry.draft
        draft.meal = .dinner
        draft.calories = 900 // macros now say ~380
        #expect(throws: WriteRejected.self) { try EntryWriter.update(entry, to: draft, in: context) }
        #expect(entry.calories == 380 && entry.meal == .snack)
    }

    @Test func deleteRemovesOnlyThatEntry() throws {
        let first = try saved()
        _ = try saved(.label)
        try EntryWriter.delete(first, in: context)
        let left = try context.fetch(FetchDescriptor<MealEntry>())
        #expect(left.count == 1 && left[0].source == .label)
    }
}
