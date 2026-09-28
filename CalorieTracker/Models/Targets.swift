import Foundation
import SwiftData

/// One version of the user's targets. A change adds a row with a new `effectiveFrom`,
/// so past days are still judged against the targets that applied then.
@Model
final class Targets {
    var effectiveFromKey: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var goalNote: String

    init(effectiveFrom: LocalDate, targets: MacroTargets, goalNote: String = "") {
        effectiveFromKey = effectiveFrom.iso
        calories = targets.calories
        protein = targets.protein
        carbs = targets.carbs
        fat = targets.fat
        self.goalNote = goalNote
    }

    var period: TargetPeriod {
        TargetPeriod(effectiveFrom: LocalDate(iso: effectiveFromKey)!,
                     targets: MacroTargets(calories: calories, protein: protein, carbs: carbs, fat: fat))
    }
}
