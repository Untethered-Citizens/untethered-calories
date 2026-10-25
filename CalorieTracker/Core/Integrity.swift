import Foundation

/// How the numbers for an entry reached the app. This decides the logging path
/// and which `Source` is honest for the entry.
enum EntryOrigin: Equatable, Codable, Sendable {
    /// The user stated the numbers or typed out a label.
    case statedNumbers
    /// Read from a photo of a nutrition label.
    case labelPhoto
    /// A usual meal named exactly, which keeps the source it was first measured with.
    case usualMeal(storedSource: Source)
    /// A usual meal with a variation, so it's adjusted by estimate.
    case usualMealVariation
    /// A plain-words description, estimated by the model.
    case description
    /// A photo of the food itself, estimated by the model.
    case foodPhoto
    /// The user correcting an entry that's already saved (D44). The source can't change:
    /// fixing an estimate's numbers doesn't make it a label.
    case correction(of: Source)

    /// Path A commits immediately. Path B is proposed, confirmed, then committed.
    var path: LogPath {
        switch self {
        case .statedNumbers, .labelPhoto, .usualMeal, .correction: return .a
        case .usualMealVariation, .description, .foodPhoto: return .b
        }
    }

    /// The only source an entry from this origin may carry.
    var requiredSource: Source {
        switch self {
        case .statedNumbers, .labelPhoto: return .label
        case .usualMeal(let stored): return stored
        case .usualMealVariation, .description: return .estimate
        case .foodPhoto: return .photoEstimate
        case .correction(let original): return original
        }
    }
}

enum LogPath: Sendable {
    case a
    case b
}

enum IntegrityIssue: Equatable, Sendable {
    case emptyDescription
    case negativeValue(field: String)
    /// Above the app's limit for one entry, usual meal or day's targets (#42).
    case tooLarge(field: String, limit: Int)
    /// `4P + 4C + 9F` is too far from the stated calories. Values have probably
    /// landed in the wrong fields.
    case macroMismatch(statedCalories: Int, macroCalories: Int)
    case sourceMismatch(expected: Source, got: Source)
    /// A Path B estimate reached the write boundary without the user agreeing.
    case needsConfirmation
}

/// The write-boundary checks. Nothing is stored unless `issues(...)` comes back empty.
enum Integrity {
    /// The allowed relative gap between stated calories and `4P + 4C + 9F`.
    static let tolerance = 0.15
    /// Also allow a small absolute gap, so tiny items (a 5 kcal splash of milk,
    /// rounded to whole grams) aren't rejected over rounding.
    static let absoluteSlack = 10

    /// Upper limits for one entry, one usual meal, and a day's targets (#42). Far above any
    /// real meal, and far below where adding up a day could overflow. Typed numbers are
    /// already short (NumberField); these also cover numbers that come from the model.
    static let maxCalories = 20_000
    static let maxGrams = 5_000

    /// `.tooLarge` for each value above its limit.
    static func sizeIssues(calories: Int, protein: Int, carbs: Int, fat: Int) -> [IntegrityIssue] {
        [("calories", calories, maxCalories), ("protein", protein, maxGrams),
         ("carbs", carbs, maxGrams), ("fat", fat, maxGrams)]
            .filter { $0.1 > $0.2 }
            .map { .tooLarge(field: $0.0, limit: $0.2) }
    }

    /// Saturates instead of trapping, so a corrupt value can't crash the check that
    /// would refuse it, or a screen that shows it.
    static func macroCalories(protein: Int, carbs: Int, fat: Int) -> Int {
        let sum = 4 * Double(protein) + 4 * Double(carbs) + 9 * Double(fat)
        if sum >= Double(Int.max) { return .max }
        if sum <= Double(Int.min) { return .min }
        return Int(sum)
    }

    /// Returns the mismatch, if any. Entries flagged `containsAlcohol` are exempt,
    /// because alcohol's ~7 kcal/g isn't in the macros.
    /// Blind spot (by arithmetic): a protein/carbs swap passes, as both are 4 kcal/g.
    static func macroIssue(_ item: some NutritionItem) -> IntegrityIssue? {
        guard !item.containsAlcohol else { return nil }
        let fromMacros = macroCalories(protein: item.protein, carbs: item.carbs, fat: item.fat)
        let gap = abs(Double(fromMacros) - Double(item.calories))
        if gap <= Double(absoluteSlack) { return nil }
        if item.calories > 0, gap / Double(item.calories) <= tolerance { return nil }
        return .macroMismatch(statedCalories: item.calories, macroCalories: fromMacros)
    }

    /// Protein, carbs and fat scaled by one factor so they add up to `calories`, keeping
    /// their proportions. For a user who corrected the calories but not the macros.
    /// Nil when there's nothing to scale (all three are zero).
    static func macrosScaled(protein: Int, carbs: Int, fat: Int,
                             toCalories calories: Int) -> (protein: Int, carbs: Int, fat: Int)? {
        let current = macroCalories(protein: protein, carbs: carbs, fat: fat)
        guard current > 0, calories >= 0 else { return nil }
        let factor = Double(calories) / Double(current)
        return (Int((Double(protein) * factor).rounded()),
                Int((Double(carbs) * factor).rounded()),
                Int((Double(fat) * factor).rounded()))
    }

    static func issues(for draft: EntryDraft, origin: EntryOrigin, confirmedByUser: Bool) -> [IntegrityIssue] {
        var found: [IntegrityIssue] = []
        if draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append(.emptyDescription)
        }
        for (name, value) in [("calories", draft.calories), ("protein", draft.protein),
                              ("carbs", draft.carbs), ("fat", draft.fat)] where value < 0 {
            found.append(.negativeValue(field: name))
        }
        let tooLarge = sizeIssues(calories: draft.calories, protein: draft.protein, carbs: draft.carbs, fat: draft.fat)
        found += tooLarge
        // A ratio check on numbers already refused for size would only add noise.
        if tooLarge.isEmpty, let mismatch = macroIssue(draft) { found.append(mismatch) }
        if draft.source != origin.requiredSource {
            found.append(.sourceMismatch(expected: origin.requiredSource, got: draft.source))
        }
        if origin.path == .b && !confirmedByUser {
            found.append(.needsConfirmation)
        }
        return found
    }
}
