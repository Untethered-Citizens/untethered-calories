import Foundation
import SwiftData

/// A meal the user eats often, with exact numbers. Naming it exactly logs it by Path A.
@Model
final class UsualMeal {
    var name: String
    /// Other ways the user refers to it, like "my normal lunch".
    var triggerPhrases: [String]
    var mealRaw: String
    var foodDescription: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    /// The source it was first measured with, kept forever. An estimate stays an estimate.
    var sourceRaw: String
    var containsAlcohol: Bool

    init(name: String, triggerPhrases: [String] = [], meal: Meal, description: String,
         calories: Int, protein: Int, carbs: Int, fat: Int, source: Source, containsAlcohol: Bool = false) {
        self.name = name
        self.triggerPhrases = triggerPhrases
        mealRaw = meal.rawValue
        foodDescription = description
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        sourceRaw = source.rawValue
        self.containsAlcohol = containsAlcohol
    }

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snack }
    var source: Source { Source(rawValue: sourceRaw) ?? .estimate }

    /// A draft for logging this meal as-is on `date`, keeping its stored source.
    func draft(on date: LocalDate, meal slot: Meal? = nil) -> EntryDraft {
        EntryDraft(date: date, meal: slot ?? meal, description: foodDescription,
                   calories: calories, protein: protein, carbs: carbs, fat: fat,
                   source: source, containsAlcohol: containsAlcohol)
    }
}

extension UsualMeal: NutritionItem {}
