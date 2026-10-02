import Foundation

/// Totals for any group of entries, usually one day.
struct NutritionTotals: Equatable, Sendable {
    var calories = 0
    var protein = 0
    var carbs = 0
    var fat = 0
    /// Calories from entries whose source isn't `Label`.
    var estimatedCalories = 0
    var entryCount = 0

    static let zero = NutritionTotals()

    init(calories: Int = 0, protein: Int = 0, carbs: Int = 0, fat: Int = 0,
         estimatedCalories: Int = 0, entryCount: Int = 0) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.estimatedCalories = estimatedCalories
        self.entryCount = entryCount
    }

    init(_ items: [some NutritionItem]) {
        for item in items {
            calories += item.calories
            protein += item.protein
            carbs += item.carbs
            fat += item.fat
            if item.source.isEstimated { estimatedCalories += item.calories }
            entryCount += 1
        }
    }

    static func + (lhs: NutritionTotals, rhs: NutritionTotals) -> NutritionTotals {
        NutritionTotals(calories: lhs.calories + rhs.calories,
                        protein: lhs.protein + rhs.protein,
                        carbs: lhs.carbs + rhs.carbs,
                        fat: lhs.fat + rhs.fat,
                        estimatedCalories: lhs.estimatedCalories + rhs.estimatedCalories,
                        entryCount: lhs.entryCount + rhs.entryCount)
    }

    /// Whole-percent share of calories that were estimated, or nil when nothing was eaten.
    var estimatedPercent: Int? {
        guard calories > 0 else { return nil }
        return Int((Double(estimatedCalories) / Double(calories) * 100).rounded())
    }
}

/// What's left of the day's targets. Negative means over.
struct Remaining: Equatable, Sendable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    init(targets: MacroTargets, eaten: NutritionTotals) {
        calories = targets.calories - eaten.calories
        protein = targets.protein - eaten.protein
        carbs = targets.carbs - eaten.carbs
        fat = targets.fat - eaten.fat
    }

    var isOverCalories: Bool { calories < 0 }
}

/// The seven-day view's numbers, following the honesty rules:
/// today is partial and left out, days with no data are gaps and not averaged over,
/// and each day is judged against the targets that applied on that day.
struct WeekStats: Equatable, Sendable {
    /// The window, oldest first, ending on `end` (today unless paging back).
    let days: [LocalDate]
    /// True when the window contains today, which is left out of the averages.
    let includesToday: Bool
    /// Past days in the window that have data. These are the only days averaged.
    let completeDays: [LocalDate]
    /// Past days in the window with no data.
    let missingDays: [LocalDate]
    /// Average calories per complete day, rounded to the nearest 5. Nil if there are no complete days.
    let averageCalories: Int?
    let averageProtein: Double?
    let averageCarbs: Double?
    let averageFat: Double?
    let daysOverTarget: Int
    /// Share of the complete days' calories that were estimated.
    let estimatedPercent: Int?
    /// True when the first-ever logging day is among the complete days. It may be partial,
    /// and the UI should say so.
    let includesFirstLoggingDay: Bool

    init(today: LocalDate,
         ending end: LocalDate? = nil,
         dayTotals: [LocalDate: NutritionTotals],
         targetPeriods: [TargetPeriod],
         firstLoggingDay: LocalDate? = nil,
         length: Int = 7) {
        let end = min(end ?? today, today)
        days = LocalDate.range(from: end.adding(days: -(length - 1)), through: end)
        includesToday = days.contains(today)
        let past = days.filter { $0 < today }
        completeDays = past.filter { (dayTotals[$0]?.entryCount ?? 0) > 0 }
        missingDays = past.filter { (dayTotals[$0]?.entryCount ?? 0) == 0 }

        let totals = completeDays.map { dayTotals[$0]! }
        let sum = totals.reduce(NutritionTotals.zero, +)
        let n = Double(completeDays.count)
        if completeDays.isEmpty {
            averageCalories = nil
            averageProtein = nil
            averageCarbs = nil
            averageFat = nil
        } else {
            averageCalories = Rounding.nearest5(Double(sum.calories) / n)
            averageProtein = Double(sum.protein) / n
            averageCarbs = Double(sum.carbs) / n
            averageFat = Double(sum.fat) / n
        }
        daysOverTarget = completeDays.filter { day in
            dayTotals[day]!.calories > TargetHistory.effective(on: day, in: targetPeriods).calories
        }.count
        estimatedPercent = sum.estimatedPercent
        let complete = completeDays
        includesFirstLoggingDay = firstLoggingDay.map { complete.contains($0) } ?? false
        self.firstLoggingDay = includesFirstLoggingDay ? firstLoggingDay : nil
    }

    private let firstLoggingDay: LocalDate?

    /// The plain-words note under the week: what the averages cover and what they leave out.
    func honestyNote(text: LogText = LogText()) -> String {
        let short = { (day: LocalDate) in text.dayName(day, template: "MMM d") }
        var parts: [String] = []
        if let first = completeDays.first, let last = completeDays.last {
            let count = completeDays.count
            parts.append(count == 1
                ? "Averages cover 1 complete day, \(short(first))."
                : "Averages cover \(count) complete days, \(short(first)) to \(short(last)).")
        } else {
            parts.append("No complete days with data in this week, so there are no averages.")
        }
        if includesToday { parts.append("Today is left out because it isn't finished.") }
        switch missingDays.count {
        case 0: break
        case 1: parts.append("1 day had no data and isn't averaged over.")
        default: parts.append("\(missingDays.count) days had no data and aren't averaged over.")
        }
        if let firstLoggingDay {
            parts.append("\(short(firstLoggingDay)) was the first day of logging and may be incomplete.")
        }
        parts.append("Solid bars are from labels; hatched bars are estimates.")
        return parts.joined(separator: " ")
    }
}

enum Rounding {
    /// Rounds to the nearest multiple of 5, with halves going up (1,792.5 → 1,795).
    static func nearest5(_ value: Double) -> Int {
        Int((value / 5).rounded(.toNearestOrAwayFromZero)) * 5
    }
}
