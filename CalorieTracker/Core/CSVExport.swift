import Foundation

/// Builds the two export files (D52): meals.csv for the meals still in the detail window, and
/// daily.csv for every day with any data. Plain RFC 4180 CSV, so any spreadsheet opens it.
enum CSVExport {
    struct Meal: Sendable {
        var draft: EntryDraft
    }

    struct Day: Sendable {
        var date: LocalDate
        var totals: NutritionTotals
        var weightPounds: Double?
        /// One line per meal, oldest meal slot first.
        var mealLines: [String]
    }

    static let mealsHeader = ["date", "meal", "food", "calories", "protein_g", "carbs_g", "fat_g", "source", "contains_alcohol"]

    static func dailyHeader(unit: WeightUnit) -> [String] {
        ["date", "calories", "protein_g", "carbs_g", "fat_g", "estimated_calories", "entries", "weight_\(unit.rawValue)", "meals"]
    }

    /// Rows must already be in detail order (date, then meal).
    static func meals(_ drafts: [EntryDraft]) -> String {
        document(header: mealsHeader, rows: drafts.map { d in
            [d.date.iso, d.meal.rawValue, d.description, "\(d.calories)", "\(d.protein)", "\(d.carbs)",
             "\(d.fat)", d.source.rawValue, d.containsAlcohol ? "yes" : "no"]
        })
    }

    /// Oldest day first. A day with only a weight has empty nutrition columns, not zeros,
    /// so a gap stays a gap in a spreadsheet too.
    static func daily(_ days: [Day], unit: WeightUnit) -> String {
        document(header: dailyHeader(unit: unit), rows: days.sorted { $0.date < $1.date }.map { day in
            let logged = day.totals.entryCount > 0
            let number: (Int) -> String = { logged ? "\($0)" : "" }
            let weight = day.weightPounds.map { String(format: "%.1f", unit.fromPounds($0)) } ?? ""
            return [day.date.iso, number(day.totals.calories), number(day.totals.protein),
                    number(day.totals.carbs), number(day.totals.fat), number(day.totals.estimatedCalories),
                    number(day.totals.entryCount), weight, day.mealLines.joined(separator: "\n")]
        })
    }

    static func document(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field when it holds a comma, quote or line break, doubling any quotes.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
