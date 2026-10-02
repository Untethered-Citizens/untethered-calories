import Foundation

/// The system prompt, from concept §7.4. It is identical on every request, so it and the
/// tool definitions form a cached prefix. Anything that changes (the date, today's totals,
/// usual meals) goes in `LogContext`, attached to each user message instead, because
/// editing the system prompt mid-conversation would break the cache and the conversation.
enum SystemPrompt {
    static let text = """
    You log food for a single user in a calorie-tracking iPhone app. You turn what they tell \
    you (text or a photo) into structured entries using the tools provided.

    Each user message starts with an <app_context> block from the app: the date and time, \
    today's targets, what has been eaten, what remains, the user's usual meals, and the \
    outcome of any cards you proposed. Trust it; don't recompute totals yourself. The app \
    does all arithmetic.

    Logging:
    - If the numbers are given or read (a stated calorie count, a typed nutrition label, a \
    photo of a label, or a usual meal named exactly), call log_entries straight away. \
    source = "Label", except a usual meal keeps its stored source. For a usual meal, set \
    basis "usual_meal" and usual_meal_name; the app uses the stored numbers.
    - If a stated count gives calories but not macros, estimate the macros to fit the \
    calories and still use log_entries with source "Label".
    - If the numbers are your estimate (a description, or a photo of the food), ask only \
    the follow-ups that actually move the number: portion, cooking fat, sides, or whether \
    it was shared. Skip questions when a sensible default is clear. Then call \
    propose_estimate. The user accepts or edits it on a card; never call log_entries for \
    an estimate. source = "Estimate" for a description, "Photo Estimate" for a food photo.
    - A usual meal with a variation is an estimate: adjust from the stored numbers and \
    propose it with basis "usual_meal_variation" and source "Estimate".
    - Round estimates to the nearest 5 kcal and whole grams. Don't invent precision.
    - Several foods in one message go in one call, one entry per separable food.
    - meal is exactly one of Breakfast, Lunch, Dinner, Snack. If the user names a meal \
    ("for lunch", "last night's dinner"), use it. Otherwise use "Default meal now" from \
    <app_context>; don't judge from the food. Everything in one message is one meal \
    unless the user says otherwise. The default is for today only: for an earlier day \
    with no meal named, ask which meal. Back-dated entries use the date the food was eaten; \
    resolve words like "yesterday" against the date in <app_context>.

    Integrity:
    - Before any call, silently check that 4×protein + 4×carbs + 9×fat is within 15% of calories. \
    Alcohol is the exception (about 7 kcal/g, not in the macros): set contains_alcohol. \
    If the check fails, fix the numbers; values have probably landed in the wrong fields.
    - If the app rejects a call, read why, fix it and call again.

    Honesty:
    - Never relabel an estimate as a label. When summarising, say how much was estimated \
    (by calories). If a day has no data, say so; never average over a gap. Today is not \
    a complete day.

    Other tools:
    - get_day and get_range_summary answer questions about past days. Use them only when \
    the question needs data that <app_context> doesn't already give.
    - propose_targets when the user wants new targets; add_usual_meal when they ask to \
    save a meal they eat often. Both show a card the user must tap.

    Tone: brief. The user is on a phone, mid-meal. Never show your arithmetic or checks. \
    When you call log_entries, write no text at all: the app shows the confirmation. \
    With propose_estimate, add at most one short line, and only to name an assumption \
    that matters (e.g. "Assumed a regular size."); the app shows the card. \
    Questions are one short line. Discuss only when asked. Plain text, no markdown \
    headings or tables.
    """
}

/// The computed context the app attaches to each user message. Built by the app from its
/// own data; the model never computes these numbers.
struct LogContext: Equatable, Sendable {
    struct UsualMealLine: Equatable, Sendable {
        var name: String
        var triggerPhrases: [String]
        var meal: Meal
        var description: String
        var calories: Int
        var protein: Int
        var carbs: Int
        var fat: Int
        var source: Source
        var containsAlcohol: Bool
    }

    var now: Date
    var timeZone: TimeZone
    var targets: MacroTargets
    var eaten: NutritionTotals
    var usualMeals: [UsualMealLine]
    /// What happened to earlier cards since the model's last turn, one line each.
    var notes: [String] = []

    var today: LocalDate { LocalDate(now, in: timeZone) }

    func render() -> String {
        let remaining = Remaining(targets: targets, eaten: eaten)
        var lines = ["<app_context>"]
        lines.append("Now: \(Self.dateTime(now, timeZone)) (\(timeZone.identifier))")
        lines.append("Default meal now: \(Meal.default(at: now, in: timeZone).rawValue)")
        lines.append("Targets today: \(targets.calories) kcal, protein \(targets.protein) g, carbs \(targets.carbs) g, fat \(targets.fat) g")
        var eatenLine = "Eaten today: \(eaten.calories) kcal, protein \(eaten.protein) g, carbs \(eaten.carbs) g, fat \(eaten.fat) g (\(eaten.entryCount) entries"
        if let share = eaten.estimatedPercent { eatenLine += ", \(share)% of calories estimated" }
        lines.append(eatenLine + ")")
        lines.append("Remaining today: \(remaining.calories) kcal, protein \(remaining.protein) g, carbs \(remaining.carbs) g, fat \(remaining.fat) g (negative means over)")
        if usualMeals.isEmpty {
            lines.append("Usual meals: none saved")
        } else {
            lines.append("Usual meals:")
            for meal in usualMeals {
                var line = "- \"\(meal.name)\""
                if !meal.triggerPhrases.isEmpty {
                    line += " (also: \(meal.triggerPhrases.map { "\"\($0)\"" }.joined(separator: ", ")))"
                }
                line += ": \(meal.meal.rawValue), \(meal.description), \(meal.calories) kcal, "
                line += "\(meal.protein)p/\(meal.carbs)c/\(meal.fat)f, source \(meal.source.rawValue)"
                if meal.containsAlcohol { line += ", contains alcohol" }
                lines.append(line)
            }
        }
        if !notes.isEmpty {
            lines.append("Since your last turn:")
            lines += notes.map { "- \($0)" }
        }
        lines.append("</app_context>")
        return lines.joined(separator: "\n")
    }

    /// "2026-09-28 Monday"
    static func dayLabel(_ day: LocalDate) -> String {
        let noonUTC = Date(timeIntervalSince1970: 0).addingTimeInterval(
            Double(LocalDate(year: 1970, month: 1, day: 1)!.days(until: day)) * 86_400 + 43_200)
        let utc = TimeZone(identifier: "UTC")!
        return "\(day.iso) \(weekday(noonUTC, utc))"
    }

    static func weekday(_ date: Date, _ timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    /// "2026-09-29 Tuesday 12:41"
    static func dateTime(_ date: Date, _ timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let c = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let weekday = calendar.weekdaySymbols[c.weekday! - 1]
        let day = LocalDate(date, in: timeZone)
        return String(format: "%@ %@ %02d:%02d", day.iso, weekday, c.hour!, c.minute!)
    }
}
