import Testing
@testable import CalorieTracker

struct IntegrityTests {
    func draft(cal: Int, p: Int, c: Int, f: Int, source: Source = .label,
               alcohol: Bool = false, text: String = "Food") -> EntryDraft {
        EntryDraft(date: LocalDate(iso: "2026-09-26")!, meal: .lunch, description: text,
                   calories: cal, protein: p, carbs: c, fat: f, source: source, containsAlcohol: alcohol)
    }

    @Test func consistentMacrosPass() {
        // 4·17 + 4·26 + 9·19 = 343 vs 330: about 4% off.
        #expect(Integrity.macroIssue(draft(cal: 330, p: 17, c: 26, f: 19)) == nil)
    }

    @Test func rotatedMacrosFail() {
        // The pilot bug: a 480 kcal salad kit stored with 55 g fat.
        #expect(Integrity.macroIssue(draft(cal: 480, p: 12, c: 20, f: 55))
                == .macroMismatch(statedCalories: 480, macroCalories: 623))
    }

    @Test func toleranceEdge() {
        // 4·25 = 100 macro kcal vs 115 stated: a 15 kcal gap, 13% of 115, so it passes.
        #expect(Integrity.macroIssue(draft(cal: 115, p: 0, c: 25, f: 0)) == nil)
        // 100 macro kcal vs 130 stated: 23% off, beyond the absolute slack too.
        #expect(Integrity.macroIssue(draft(cal: 130, p: 0, c: 25, f: 0)) != nil)
    }

    @Test func alcoholIsExempt() {
        #expect(Integrity.macroIssue(draft(cal: 125, p: 0, c: 4, f: 0, alcohol: true)) == nil)
        #expect(Integrity.macroIssue(draft(cal: 125, p: 0, c: 4, f: 0)) != nil)
    }

    @Test func tinyItemsGetAbsoluteSlack() {
        #expect(Integrity.macroIssue(draft(cal: 5, p: 0, c: 0, f: 0)) == nil)
        #expect(Integrity.macroIssue(draft(cal: 0, p: 0, c: 0, f: 0)) == nil)
    }

    @Test func proteinCarbSwapIsAKnownBlindSpot() {
        // Both are 4 kcal/g, so the arithmetic can't see this swap. Documented, not fixed.
        #expect(Integrity.macroIssue(draft(cal: 330, p: 26, c: 17, f: 19)) == nil)
    }

    @Test func pathAWritesWithoutConfirmation() {
        let issues = Integrity.issues(for: draft(cal: 330, p: 17, c: 26, f: 19),
                                      origin: .statedNumbers, confirmedByUser: false)
        #expect(issues.isEmpty)
    }

    @Test func pathBNeedsConfirmation() {
        let d = draft(cal: 330, p: 17, c: 26, f: 19, source: .estimate)
        #expect(Integrity.issues(for: d, origin: .description, confirmedByUser: false) == [.needsConfirmation])
        #expect(Integrity.issues(for: d, origin: .description, confirmedByUser: true).isEmpty)
    }

    @Test func estimateCannotBeRelabelled() {
        let labelled = draft(cal: 330, p: 17, c: 26, f: 19, source: .label)
        #expect(Integrity.issues(for: labelled, origin: .foodPhoto, confirmedByUser: true)
                == [.sourceMismatch(expected: .photoEstimate, got: .label)])
        #expect(Integrity.issues(for: labelled, origin: .usualMeal(storedSource: .estimate), confirmedByUser: false)
                == [.sourceMismatch(expected: .estimate, got: .label)])
        #expect(Integrity.issues(for: labelled, origin: .usualMealVariation, confirmedByUser: true)
                == [.sourceMismatch(expected: .estimate, got: .label)])
    }

    @Test func usualMealKeepsItsStoredSource() {
        let d = draft(cal: 330, p: 17, c: 26, f: 19, source: .estimate)
        #expect(EntryOrigin.usualMeal(storedSource: .estimate).path == .a)
        #expect(Integrity.issues(for: d, origin: .usualMeal(storedSource: .estimate), confirmedByUser: false).isEmpty)
    }

    @Test func rejectsEmptyTextAndNegatives() {
        let issues = Integrity.issues(for: draft(cal: -5, p: 0, c: 0, f: 0, text: "  "),
                                      origin: .statedNumbers, confirmedByUser: false)
        #expect(issues.contains(.emptyDescription))
        #expect(issues.contains(.negativeValue(field: "calories")))
    }

    @Test func syntheticFixtureIsInternallyConsistent() {
        for entry in SyntheticWeek.entries {
            #expect(Integrity.issues(for: entry, origin: SyntheticWeek.origin(for: entry),
                                     confirmedByUser: true).isEmpty, "\(entry.description)")
        }
    }
}

struct MacroScalingTests {
    func draft(cal: Int, p: Int, c: Int, f: Int) -> EntryDraft {
        EntryDraft(date: LocalDate(iso: "2026-09-26")!, meal: .dinner, description: "Dinner",
                   calories: cal, protein: p, carbs: c, fat: f, source: .estimate, containsAlcohol: false)
    }

    @Test func scalingKeepsProportionsAndPassesTheCheck() throws {
        // Issue #3: calories corrected from 600 to 800, macros left as they were.
        var edited = draft(cal: 800, p: 30, c: 60, f: 20)   // macros: 540 cal
        #expect(Integrity.macroIssue(edited) != nil)
        let scaled = try #require(Integrity.macrosScaled(protein: 30, carbs: 60, fat: 20, toCalories: 800))
        #expect(scaled.protein == 44 && scaled.carbs == 89 && scaled.fat == 30)
        edited.protein = scaled.protein; edited.carbs = scaled.carbs; edited.fat = scaled.fat
        #expect(Integrity.macroIssue(edited) == nil)
    }

    @Test func scalingDown() throws {
        let scaled = try #require(Integrity.macrosScaled(protein: 40, carbs: 100, fat: 30, toCalories: 300))
        #expect(Integrity.macroIssue(draft(cal: 300, p: scaled.protein, c: scaled.carbs, f: scaled.fat)) == nil)
    }

    @Test func nothingToScale() {
        #expect(Integrity.macrosScaled(protein: 0, carbs: 0, fat: 0, toCalories: 500) == nil)
    }

    @Test func refusedSaveIsExplainedPerItem() {
        let drafts = [draft(cal: 300, p: 20, c: 30, f: 10), draft(cal: 800, p: 30, c: 60, f: 20)]
        let rejected = WriteRejected(issues: [1: [.macroMismatch(statedCalories: 800, macroCalories: 540)]])
        let text = EntryEditView.explain(rejected, drafts: drafts, saveTitle: "Log")
        #expect(text.contains("Item 2: protein, carbs and fat add up to 540 cal, but calories say 800 cal."))
        #expect(text.contains("Then tap Log."))
        #expect(!text.contains("Item 1"))
    }
}
