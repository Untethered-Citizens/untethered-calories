import Foundation
import SwiftData

/// Editing and deleting usual meals from Settings (D54). New ones still come from the chat.
/// Entries already logged from a meal are copies, so changing the meal never rewrites history.
@MainActor
enum UsualMealStore {
    /// Everything about a usual meal the user may change. The source isn't here: it stays
    /// what the meal was first measured with, so an estimate never turns into a label.
    struct Edit: Equatable {
        var name: String
        var triggerPhrases: [String]
        var meal: Meal
        var description: String
        var calories: Int
        var protein: Int
        var carbs: Int
        var fat: Int
        var containsAlcohol: Bool

        init(_ usual: UsualMeal) {
            name = usual.name
            triggerPhrases = usual.triggerPhrases
            meal = usual.meal
            description = usual.foodDescription
            calories = usual.calories
            protein = usual.protein
            carbs = usual.carbs
            fat = usual.fat
            containsAlcohol = usual.containsAlcohol
        }
    }

    enum Problem: Error, Equatable {
        case emptyName
        /// Another usual meal already answers to this name or phrase.
        case nameTaken(String)
        case integrity([IntegrityIssue])

        var message: String {
            switch self {
            case .emptyName: "Give the meal a name."
            case .nameTaken(let name): "Another usual meal already goes by \"\(name)\"."
            case .integrity(let issues): issues.map(UsualMealStore.describe).joined(separator: " ")
            }
        }
    }

    /// "my normal lunch, the usual" → ["my normal lunch", "the usual"]
    static func phrases(from text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func problems(with edit: Edit, for usual: UsualMeal, among all: [UsualMeal]) -> Problem? {
        let name = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .emptyName }

        let taken = all.filter { $0 !== usual }.flatMap { [$0.name] + $0.triggerPhrases }.map(ToolRunner.normalise)
        for wanted in [name] + edit.triggerPhrases where taken.contains(ToolRunner.normalise(wanted)) {
            return .nameTaken(wanted)
        }

        let draft = EntryDraft(date: LocalDate.today(), meal: edit.meal, description: edit.description,
                               calories: edit.calories, protein: edit.protein, carbs: edit.carbs, fat: edit.fat,
                               source: usual.source, containsAlcohol: edit.containsAlcohol)
        let issues = Integrity.issues(for: draft, origin: .correction(of: usual.source), confirmedByUser: true)
        return issues.isEmpty ? nil : .integrity(issues)
    }

    static func update(_ usual: UsualMeal, with edit: Edit, in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<UsualMeal>())
        if let problem = problems(with: edit, for: usual, among: all) { throw problem }
        usual.name = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        usual.triggerPhrases = edit.triggerPhrases
        usual.mealRaw = edit.meal.rawValue
        usual.foodDescription = edit.description.trimmingCharacters(in: .whitespacesAndNewlines)
        usual.calories = edit.calories
        usual.protein = edit.protein
        usual.carbs = edit.carbs
        usual.fat = edit.fat
        usual.containsAlcohol = edit.containsAlcohol
        try context.save()
    }

    static func delete(_ usual: UsualMeal, in context: ModelContext) throws {
        context.delete(usual)
        try context.save()
    }

    nonisolated private static func describe(_ issue: IntegrityIssue) -> String {
        switch issue {
        case .emptyDescription:
            "Add a description."
        case .negativeValue(let field):
            "\(field.capitalized) can't be negative."
        case .tooLarge(let field, let limit):
            "\(field.capitalized) can be at most \(limit.formatted())\(field == "calories" ? "" : " g")."
        case .macroMismatch(let stated, let fromMacros):
            "The macros add up to \(fromMacros) calories, too far from \(stated). Check the numbers, or turn on Contains alcohol if it does."
        case .sourceMismatch, .needsConfirmation:
            "These numbers can't be saved."
        }
    }
}
