import Foundation

/// The app's own wording for logging: confirmations and local answers. Deterministic,
/// with no model call, so the numbers in them are always the app's numbers.
struct LogText {
    var locale: Locale = .current

    private func n(_ value: Int) -> String { value.formatted(.number.locale(locale)) }

    /// "Logged lunch — BLT with avocado, 765 cal (estimate). 1,005 of 1,785 today, 780 left."
    /// Back-dated entries name their day and give that day's total instead.
    func confirmation(entries: [EntryDraft], today: LocalDate,
                      dayTotals: [LocalDate: NutritionTotals],
                      targets: (LocalDate) -> MacroTargets) -> String {
        let byDay = Dictionary(grouping: entries, by: \.date)
        return byDay.keys.sorted().map { day in
            let items = byDay[day]!.sorted { $0.meal < $1.meal }
            var parts: [String] = []
            var lastMeal: Meal?
            for item in items {
                var part = ""
                if item.meal != lastMeal { part += "\(item.meal.rawValue.lowercased()) — " }
                part += "\(item.description), \(n(item.calories)) cal (\(item.source.rawValue.lowercased()))"
                parts.append(part)
                lastMeal = item.meal
            }
            let eaten = dayTotals[day] ?? .zero
            let target = targets(day)
            if day == today {
                return "Logged \(parts.joined(separator: "; ")). \(todayStatus(eaten: eaten, target: target))"
            }
            return "Logged for \(dayName(day)): \(parts.joined(separator: "; ")). "
                + "That day: \(n(eaten.calories)) of \(n(target.calories))."
        }.joined(separator: " ")
    }

    /// "1,005 of 1,785 today, 780 left." or "1,905 of 1,785 today, 120 over."
    func todayStatus(eaten: NutritionTotals, target: MacroTargets) -> String {
        let left = target.calories - eaten.calories
        let tail = left >= 0 ? "\(n(left)) left" : "\(n(-left)) over"
        return "\(n(eaten.calories)) of \(n(target.calories)) today, \(tail)."
    }

    /// The local answer to "calories left?" and similar. No model call.
    func remainingAnswer(eaten: NutritionTotals, target: MacroTargets) -> String {
        let remaining = Remaining(targets: target, eaten: eaten)
        let head = remaining.calories >= 0
            ? "\(n(remaining.calories)) cal left today"
            : "\(n(-remaining.calories)) cal over today"
        func macro(_ name: String, _ value: Int) -> String {
            value >= 0 ? "\(name) \(n(value)) g left" : "\(name) \(n(-value)) g over"
        }
        return "\(head) (\(n(eaten.calories)) of \(n(target.calories)) eaten). "
            + [macro("Protein", remaining.protein), macro("carbs", remaining.carbs), macro("fat", remaining.fat)]
                .joined(separator: ", ") + "."
    }

    /// "Fri Oct 2" by default. `template` is a date-format template, e.g. "EEEE MMM d".
    func dayName(_ day: LocalDate, template: String = "EEE MMM d") -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// Recognises the simple "how much is left today?" questions the app answers itself.
/// Deliberately narrow: anything open-ended ("what should I eat to hit protein?") or about
/// another day goes to the model.
enum LocalQuery {
    static func isRemainingQuestion(_ text: String) -> Bool {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty, cleaned.count <= 8 else { return false }
        let words = Set(cleaned)
        let joined = cleaned.joined(separator: " ")

        let excluded: Set<String> = ["should", "could", "eat", "eating", "suggest", "idea", "ideas",
                                     "recommend", "dinner", "lunch", "breakfast", "snack", "yesterday",
                                     "week", "month", "monday", "tuesday", "wednesday", "thursday",
                                     "friday", "saturday", "sunday", "log", "add", "had", "ate"]
        guard words.isDisjoint(with: excluded) else { return false }

        let phrases = ["how am i doing", "how'm i doing", "where am i at", "where am i", "what's left",
                       "whats left", "how much is left", "how much left", "how much do i have"]
        if phrases.contains(where: { joined.contains($0) }) { return true }
        // "left" alone is too loose ("I left half the sandwich"), so it needs a word about the budget.
        let asksRemaining = !words.isDisjoint(with: ["left", "remaining", "remain"])
        let aboutBudget: Set<String> = ["calories", "calorie", "cals", "cal", "kcal", "protein", "carbs",
                                        "fat", "macros", "budget", "today", "much", "many"]
        return asksRemaining && (cleaned.count == 1 || !words.isDisjoint(with: aboutBudget))
    }
}
