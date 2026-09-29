import Testing
@testable import CalorieTracker

struct TargetCalculatorTests {
    /// A made-up person: 40-year-old male, 5′10″ (177.8 cm), 180 lb (81.65 kg), lightly active.
    let base = TargetCalculator.Input(sex: .male, age: 40, heightCm: TargetCalculator.cm(feet: 5, inches: 10),
                                      weightKg: WeightUnit.kg.fromPounds(180), activity: .light, goal: .loseFaster)

    @Test func mifflinStJeorWithActivityAndGoal() {
        // Resting: 10×81.65 + 6.25×177.8 − 5×40 + 5 = 1,732.6. ×1.375 = 2,382 → 2,380 (nearest 5).
        let result = TargetCalculator.suggest(base)
        #expect(result.maintenance == 2380)
        #expect(result.targets.calories == 1880)
        #expect(!result.raisedToMinimum)
    }

    @Test func macrosFillTheCaloriesAndPassTheIntegrityCheck() {
        let t = TargetCalculator.suggest(base).targets
        #expect(t.protein == 131)             // 1.6 g × 81.65 kg
        #expect(t.fat == 63)                  // 30% of 1,880 ÷ 9
        let fromMacros = Integrity.macroCalories(protein: t.protein, carbs: t.carbs, fat: t.fat)
        #expect(abs(fromMacros - t.calories) <= 5)
    }

    @Test func neverSuggestsBelowTheMinimum() {
        var small = base
        small.sex = .female
        small.age = 70
        small.heightCm = 150
        small.weightKg = 45
        small.activity = .sedentary
        let result = TargetCalculator.suggest(small)
        #expect(result.targets.calories == 1200)
        #expect(result.raisedToMinimum)
        #expect(result.targets.carbs >= 0)
    }

    @Test func maintainAndGainAdjustUpward() {
        var maintain = base
        maintain.goal = .maintain
        var gain = base
        gain.goal = .gain
        #expect(TargetCalculator.suggest(maintain).targets.calories == 2380)
        #expect(TargetCalculator.suggest(gain).targets.calories == 2630)
    }

    @Test func femaleOffsetIsLower() {
        var female = base
        female.sex = .female
        // The formula differs by 166 kcal of resting energy between sexes, before activity.
        #expect(TargetCalculator.suggest(base).maintenance - TargetCalculator.suggest(female).maintenance > 200)
    }

    @Test func heightConversion() {
        #expect(abs(TargetCalculator.cm(feet: 6, inches: 0) - 182.88) < 0.001)
    }
}
