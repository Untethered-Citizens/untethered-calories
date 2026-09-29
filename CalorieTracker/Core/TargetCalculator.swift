import Foundation

/// A simple starting point for daily targets, for people who don't know their numbers.
/// Mifflin–St Jeor for resting energy, times an activity factor, plus a goal adjustment.
/// The inputs are used once and never stored; only the resulting targets are saved.
enum TargetCalculator {
    enum Sex: String, CaseIterable, Identifiable, Sendable {
        case female, male
        var id: String { rawValue }
    }

    enum Activity: String, CaseIterable, Identifiable, Sendable {
        case sedentary, light, moderate, active
        var id: String { rawValue }

        var factor: Double {
            switch self {
            case .sedentary: 1.2
            case .light: 1.375
            case .moderate: 1.55
            case .active: 1.725
            }
        }

        var label: String {
            switch self {
            case .sedentary: "Mostly sitting"
            case .light: "Light exercise 1–3 days a week"
            case .moderate: "Moderate exercise 3–5 days a week"
            case .active: "Hard exercise 6–7 days a week"
            }
        }
    }

    enum Goal: String, CaseIterable, Identifiable, Sendable {
        case loseFaster, loseSlower, maintain, gain
        var id: String { rawValue }

        /// Daily calorie change. About 3,500 kcal per lb, so 500 a day is roughly 1 lb a week.
        var dailyAdjustment: Int {
            switch self {
            case .loseFaster: -500
            case .loseSlower: -250
            case .maintain: 0
            case .gain: 250
            }
        }

        func label(_ unit: WeightUnit) -> String {
            switch (self, unit) {
            case (.loseFaster, .lb): "Lose about 1 lb a week"
            case (.loseFaster, .kg): "Lose about 0.5 kg a week"
            case (.loseSlower, .lb): "Lose about ½ lb a week"
            case (.loseSlower, .kg): "Lose about 0.25 kg a week"
            case (.maintain, _): "Stay where I am"
            case (.gain, .lb): "Gain about ½ lb a week"
            case (.gain, .kg): "Gain about 0.25 kg a week"
            }
        }
    }

    struct Input: Sendable {
        var sex: Sex
        var age: Int
        var heightCm: Double
        var weightKg: Double
        var activity: Activity
        var goal: Goal
    }

    struct Result: Equatable, Sendable {
        var targets: MacroTargets
        /// Calories before the goal adjustment: roughly what keeps weight steady.
        var maintenance: Int
        /// True when the goal would have gone below the minimum, so the minimum was used instead.
        var raisedToMinimum: Bool
    }

    /// Common guidance: don't go below these without a professional's supervision.
    static func minimumCalories(for sex: Sex) -> Int { sex == .female ? 1200 : 1500 }

    /// Protein 1.6 g per kg of body weight, fat 30% of calories, carbs the rest.
    static let proteinPerKg = 1.6
    static let fatShare = 0.30

    static func suggest(_ input: Input) -> Result {
        let resting = 10 * input.weightKg + 6.25 * input.heightCm - 5 * Double(input.age)
            + (input.sex == .male ? 5 : -161)
        let maintenance = roundTo5(resting * input.activity.factor)
        let wanted = maintenance + input.goal.dailyAdjustment
        let floor = minimumCalories(for: input.sex)
        let calories = max(wanted, floor)

        let fat = Int((Double(calories) * fatShare / 9).rounded())
        var protein = Int((input.weightKg * proteinPerKg).rounded())
        // Keep protein and fat inside the calorie budget, leaving carbs at zero or more.
        protein = min(protein, (calories - 9 * fat) / 4)
        let carbs = max(0, (calories - 4 * protein - 9 * fat) / 4)

        return Result(targets: MacroTargets(calories: calories, protein: protein, carbs: carbs, fat: fat),
                      maintenance: maintenance,
                      raisedToMinimum: wanted < floor)
    }

    private static func roundTo5(_ value: Double) -> Int { Int((value / 5).rounded()) * 5 }

    // MARK: Units

    static func cm(feet: Int, inches: Int) -> Double { Double(feet * 12 + inches) * 2.54 }
}
