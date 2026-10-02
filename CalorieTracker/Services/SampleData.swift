#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData

/// Four weeks of made-up meals and weights, so the dashboard can be seen in the simulator.
/// Simulator debug builds only: this code doesn't exist in a build for a real iPhone.
/// Everything is synthetic and goes through the write boundary like real logging.
enum SampleData {
    private struct Food {
        var description: String
        var calories, protein, carbs, fat: Int
        var source: Source
        var alcohol = false
    }

    private static let breakfasts = [
        Food(description: "Greek yogurt with berries", calories: 220, protein: 20, carbs: 24, fat: 5, source: .label),
        Food(description: "Oatmeal with banana", calories: 310, protein: 9, carbs: 58, fat: 6, source: .estimate),
        Food(description: "Two eggs and toast", calories: 350, protein: 20, carbs: 28, fat: 17, source: .estimate),
    ]
    private static let lunches = [
        Food(description: "Chicken salad", calories: 450, protein: 38, carbs: 18, fat: 25, source: .estimate),
        Food(description: "Turkey sandwich", calories: 380, protein: 22, carbs: 38, fat: 14, source: .estimate),
        Food(description: "Burrito bowl", calories: 650, protein: 35, carbs: 70, fat: 24, source: .photoEstimate),
    ]
    private static let dinners = [
        Food(description: "Salmon, rice and broccoli", calories: 600, protein: 40, carbs: 55, fat: 22, source: .estimate),
        Food(description: "Pasta with meat sauce", calories: 720, protein: 32, carbs: 90, fat: 24, source: .photoEstimate),
        Food(description: "Chicken stir-fry", calories: 540, protein: 30, carbs: 52, fat: 22, source: .photoEstimate),
        Food(description: "Frozen lasagna", calories: 590, protein: 30, carbs: 62, fat: 24, source: .label),
    ]
    private static let snacks = [
        Food(description: "Protein bar", calories: 210, protein: 20, carbs: 22, fat: 7, source: .label),
        Food(description: "Apple", calories: 95, protein: 0, carbs: 25, fat: 0, source: .estimate),
        Food(description: "Glass of red wine", calories: 125, protein: 0, carbs: 4, fat: 0, source: .label, alcohol: true),
    ]

    /// Replaces all meals and daily rows with the sample. Targets are kept.
    static func load(into context: ModelContext, today: LocalDate, detailWindowDays: Int) throws {
        try context.delete(model: MealEntry.self)
        try context.delete(model: DailySummary.self)

        var random = SeededRandom(seed: 42)
        let gaps: Set<Int> = [5, 16]
        var pending: [PendingEntry] = []
        for back in stride(from: 27, through: 0, by: -1) where !gaps.contains(back) {
            let day = today.adding(days: -back)
            var meals: [(Meal, Food)] = [
                (.breakfast, breakfasts[random.next(breakfasts.count)]),
                (.lunch, lunches[random.next(lunches.count)]),
            ]
            if back > 0 {
                meals.append((.dinner, dinners[random.next(dinners.count)]))
                for _ in 0..<random.next(3) { meals.append((.snack, snacks[random.next(snacks.count)])) }
            }
            for (meal, food) in meals {
                let draft = EntryDraft(date: day, meal: meal, description: food.description,
                                       calories: food.calories, protein: food.protein, carbs: food.carbs,
                                       fat: food.fat, source: food.source, containsAlcohol: food.alcohol)
                let origin: EntryOrigin = switch food.source {
                case .label: .statedNumbers
                case .estimate: .description
                case .photoEstimate: .foodPhoto
                }
                pending.append(PendingEntry(draft: draft, origin: origin))
            }
        }
        try EntryWriter.commit(pending, confirmedByUser: true, in: context)

        // About 1 lb a week down, with day-to-day water noise, one skipped day in six and a
        // two-day gap (still four readings in every week, so the average runs throughout).
        for back in stride(from: 27, through: 0, by: -1) where back % 6 != 2 && !(12...13).contains(back) {
            let trend = 174.0 - Double(27 - back) * 0.15
            let noise = Double(random.next(13) - 6) / 10
            let row = try DailySummaryStore.getOrCreate(today.adding(days: -back), in: context)
            row.weight = ((trend + noise) * 10).rounded() / 10
        }
        try context.save()
        try RollUp.run(in: context, today: today, detailWindowDays: detailWindowDays)
        try context.save()
    }
}

/// A tiny repeatable generator, so the sample is the same every time.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(upperBound))
    }
}
#endif
