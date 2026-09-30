import Foundation

/// The tools the model can call. The app runs every one of them itself; there is no
/// tool that deletes anything. Every number is a named field (pilot lesson: never positional).
enum LogTool: String, CaseIterable, Sendable {
    case logEntries = "log_entries"
    case proposeEstimate = "propose_estimate"
    case getDay = "get_day"
    case getRangeSummary = "get_range_summary"
    case proposeTargets = "propose_targets"
    case addUsualMeal = "add_usual_meal"
}

/// Where the numbers in an entry came from, as the model reports it. This picks the
/// logging path: `log_entries` only takes Path A bases, `propose_estimate` only Path B.
enum EntryBasis: String, Codable, CaseIterable, Sendable {
    case statedNumbers = "stated_numbers"
    case labelPhoto = "label_photo"
    case usualMeal = "usual_meal"
    case description
    case foodPhoto = "food_photo"
    case usualMealVariation = "usual_meal_variation"

    static let pathA: [EntryBasis] = [.statedNumbers, .labelPhoto, .usualMeal]
    static let pathB: [EntryBasis] = [.description, .foodPhoto, .usualMealVariation]
}

/// One entry as the model sends it.
struct ToolEntry: Codable, Equatable, Sendable {
    var date: String
    var meal: String
    var description: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var source: String
    var containsAlcohol: Bool
    var basis: EntryBasis
    /// The usual meal named, for the usual-meal bases. Empty otherwise.
    var usualMealName: String

    enum CodingKeys: String, CodingKey {
        case date, meal, description, calories, protein, carbs, fat, source, basis
        case containsAlcohol = "contains_alcohol"
        case usualMealName = "usual_meal_name"
    }
}

struct EntriesInput: Codable, Sendable {
    var entries: [ToolEntry]
}

struct DayInput: Codable, Sendable {
    var date: String
}

struct RangeInput: Codable, Sendable {
    var from: String
    var to: String
}

struct TargetsInput: Codable, Equatable, Sendable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var effectiveFrom: String
    var goalNote: String

    enum CodingKeys: String, CodingKey {
        case calories, protein, carbs, fat
        case effectiveFrom = "effective_from"
        case goalNote = "goal_note"
    }
}

struct UsualMealInput: Codable, Equatable, Sendable {
    var name: String
    var triggerPhrases: [String]
    var meal: String
    var description: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var source: String
    var containsAlcohol: Bool

    enum CodingKeys: String, CodingKey {
        case name, meal, description, calories, protein, carbs, fat, source
        case triggerPhrases = "trigger_phrases"
        case containsAlcohol = "contains_alcohol"
    }
}

extension LogTool {
    /// Tool definitions for the Messages API. The order and content never change within
    /// a build, so they stay in the cached prefix. `strict` is added only for models that
    /// support it.
    static func definitions(strict: Bool) -> [JSONValue] {
        allCases.map { tool in
            var definition: [String: JSONValue] = [
                "name": .string(tool.rawValue),
                "description": .string(tool.summary),
                "input_schema": tool.schema,
            ]
            if strict { definition["strict"] = true }
            return .object(definition)
        }
    }

    var summary: String {
        switch self {
        case .logEntries:
            "Write entries whose numbers were given or read, not estimated: a stated calorie count, a typed nutrition label, a photo of a label, or a usual meal named exactly. The app writes them at once and shows the user a confirmation, so don't repeat it. All foods from one message go in one call."
        case .proposeEstimate:
            "Propose entries whose numbers are your estimate: a description, a photo of the food, or a usual meal with a variation. Nothing is written: the app shows a card and the user taps Accept or Edit. You'll be told the outcome in the next message."
        case .getDay:
            "Get one day's entries and totals, with that day's targets."
        case .getRangeSummary:
            "Get daily totals for a date range (at most 92 days): calories, macros, estimated share and weight per day, with averages over complete days only. Days with no data are listed as gaps. Today is partial and left out of averages."
        case .proposeTargets:
            "Propose new daily targets. The app shows an Apply card; nothing changes until the user taps it. effective_from must be today or later."
        case .addUsualMeal:
            "Propose saving a meal the user eats often, with exact numbers. The app shows a card; nothing is saved until the user taps Save. source is the source the numbers were first measured with."
        }
    }

    var schema: JSONValue {
        switch self {
        case .logEntries: Self.entriesSchema(bases: EntryBasis.pathA)
        case .proposeEstimate: Self.entriesSchema(bases: EntryBasis.pathB)
        case .getDay:
            Self.object(["date": Self.dateField("The day, YYYY-MM-DD.")])
        case .getRangeSummary:
            Self.object(["from": Self.dateField("First day, YYYY-MM-DD."),
                         "to": Self.dateField("Last day, YYYY-MM-DD.")])
        case .proposeTargets:
            Self.object([
                "calories": Self.integer("Daily calories."),
                "protein": Self.integer("Grams of protein."),
                "carbs": Self.integer("Grams of carbohydrate."),
                "fat": Self.integer("Grams of fat."),
                "effective_from": Self.dateField("First day the targets apply, YYYY-MM-DD. Today or later."),
                "goal_note": ["type": "string", "description": "Short goal, e.g. \"lose about 1 lb a week\". Empty if none."],
            ])
        case .addUsualMeal:
            Self.object([
                "name": ["type": "string", "description": "What the user calls it, e.g. \"usual breakfast\"."],
                "trigger_phrases": ["type": "array", "items": ["type": "string"],
                                    "description": "Other ways the user refers to it. Can be empty."],
                "meal": Self.mealField,
                "description": ["type": "string", "description": "What it is, in plain words. Short."],
                "calories": Self.integer("Calories."),
                "protein": Self.integer("Grams of protein."),
                "carbs": Self.integer("Grams of carbohydrate."),
                "fat": Self.integer("Grams of fat."),
                "source": Self.sourceField,
                "contains_alcohol": ["type": "boolean", "description": "True if it includes alcohol."],
            ])
        }
    }

    private static func entriesSchema(bases: [EntryBasis]) -> JSONValue {
        let entry = object([
            "date": dateField("The day the food was eaten, YYYY-MM-DD. Back-dating is normal."),
            "meal": mealField,
            "description": ["type": "string", "description": "What was eaten, in plain words. Short."],
            "calories": integer("Calories. Estimates rounded to the nearest 5."),
            "protein": integer("Grams of protein."),
            "carbs": integer("Grams of carbohydrate."),
            "fat": integer("Grams of fat."),
            "source": sourceField,
            "contains_alcohol": ["type": "boolean",
                                 "description": "True if the entry includes alcohol, which exempts it from the macro check."],
            "basis": ["type": "string", "enum": .array(bases.map { .string($0.rawValue) }),
                      "description": "Where the numbers came from."],
            "usual_meal_name": ["type": "string",
                                "description": "The usual meal's name for the usual-meal bases, otherwise empty."],
        ])
        return object(["entries": ["type": "array", "items": entry, "description": "One item per food."]])
    }

    private static func object(_ properties: [String: JSONValue]) -> JSONValue {
        [
            "type": "object",
            "properties": .object(properties),
            "required": .array(properties.keys.sorted().map { .string($0) }),
            "additionalProperties": false,
        ]
    }

    private static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }

    private static func dateField(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    private static let mealField: JSONValue = [
        "type": "string", "enum": .array(Meal.allCases.map { .string($0.rawValue) }),
    ]

    private static let sourceField: JSONValue = [
        "type": "string", "enum": .array(Source.allCases.map { .string($0.rawValue) }),
    ]
}

extension EntryBasis {
    /// How the app treats an entry with this basis at the write boundary. Usual meals are
    /// resolved against the stored meal first, so the stored source applies.
    func origin(usualMealSource: Source?) -> EntryOrigin {
        switch self {
        case .statedNumbers: .statedNumbers
        case .labelPhoto: .labelPhoto
        case .usualMeal: .usualMeal(storedSource: usualMealSource ?? .label)
        case .description: .description
        case .foodPhoto: .foodPhoto
        case .usualMealVariation: .usualMealVariation
        }
    }
}
