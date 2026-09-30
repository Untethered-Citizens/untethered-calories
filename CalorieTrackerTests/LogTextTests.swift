import Foundation
import Testing
@testable import CalorieTracker

struct LogTextTests {
    let text = LogText(locale: Locale(identifier: "en_US"))
    let today = LocalDate(iso: "2026-09-29")!
    let targets = MacroTargets(calories: 1785, protein: 145, carbs: 165, fat: 60)

    private func draft(_ meal: Meal, _ description: String, _ calories: Int, _ source: Source,
                       on date: LocalDate? = nil) -> EntryDraft {
        EntryDraft(date: date ?? today, meal: meal, description: description, calories: calories,
                   protein: 0, carbs: 0, fat: 0, source: source)
    }

    @Test func confirmationMatchesTheConcept() {
        let line = text.confirmation(entries: [draft(.lunch, "BLT with avocado and side salad", 765, .estimate)],
                                     today: today, dayTotals: [today: NutritionTotals(calories: 1005)],
                                     targets: { _ in targets })
        #expect(line == "Logged lunch — BLT with avocado and side salad, 765 cal (estimate). 1,005 of 1,785 today, 780 left.")
    }

    @Test func severalFoodsShareTheMealName() {
        let line = text.confirmation(entries: [draft(.dinner, "Baked tofu", 180, .label),
                                               draft(.dinner, "Cauliflower gratin", 420, .photoEstimate)],
                                     today: today, dayTotals: [today: NutritionTotals(calories: 1900)],
                                     targets: { _ in targets })
        #expect(line == "Logged dinner — Baked tofu, 180 cal (label); Cauliflower gratin, 420 cal (photo estimate). 1,900 of 1,785 today, 115 over.")
    }

    @Test func backDatedEntryNamesItsDay() {
        let monday = LocalDate(iso: "2026-09-28")!
        let line = text.confirmation(entries: [draft(.dinner, "Pizza", 800, .estimate, on: monday)],
                                     today: today, dayTotals: [monday: NutritionTotals(calories: 2100)],
                                     targets: { _ in targets })
        #expect(line == "Logged for Mon, Sep 28: dinner — Pizza, 800 cal (estimate). That day: 2,100 of 1,785.")
    }

    @Test func remainingAnswer() {
        let answer = text.remainingAnswer(eaten: NutritionTotals(calories: 1005, protein: 85, carbs: 170, fat: 40),
                                          target: targets)
        #expect(answer == "780 cal left today (1,005 of 1,785 eaten). Protein 60 g left, carbs 5 g over, fat 20 g left.")
    }

    @Test(arguments: ["calories left?", "How many calories do I have left", "what's left", "Remaining?",
                      "how am I doing today", "protein left?", "how much is left"])
    func recognisesRemainingQuestions(_ question: String) {
        #expect(LocalQuery.isRemainingQuestion(question))
    }

    @Test(arguments: ["I left half the sandwich", "what should I eat with 500 left?", "calories left yesterday?",
                      "had a burrito for lunch", "how many calories in a banana", "",
                      "what can I have for dinner to hit my protein with what's left"])
    func leavesOtherQuestionsToTheModel(_ message: String) {
        #expect(!LocalQuery.isRemainingQuestion(message))
    }
}

struct LogToolTests {
    @Test func everySchemaIsStrictReady() throws {
        func check(_ schema: JSONValue, path: String) {
            guard case .object(let node) = schema else { return }
            if node["type"] == "object" {
                #expect(node["additionalProperties"] == .bool(false), "\(path) allows extra properties")
                if case .object(let properties) = node["properties"], case .array(let required) = node["required"] {
                    #expect(Set(required.compactMap(\.stringValue)) == Set(properties.keys), "\(path) has optional fields")
                    for (key, value) in properties { check(value, path: "\(path).\(key)") }
                }
            }
            if let items = node["items"] { check(items, path: "\(path)[]") }
        }
        for tool in LogTool.allCases { check(tool.schema, path: tool.rawValue) }
    }

    @Test func pathsSplitBetweenTools() throws {
        func bases(_ tool: LogTool) -> [String] {
            let basis = tool.schema["properties"]?["entries"]?["items"]?["properties"]?["basis"]?["enum"]
            guard case .array(let values) = basis else { return [] }
            return values.compactMap(\.stringValue)
        }
        #expect(bases(.logEntries) == ["stated_numbers", "label_photo", "usual_meal"])
        #expect(bases(.proposeEstimate) == ["description", "food_photo", "usual_meal_variation"])
    }

    @Test func definitionsAreByteStable() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(LogTool.definitions(strict: true)) == encoder.encode(LogTool.definitions(strict: true)))
    }

    @Test func readsModelCapabilities() throws {
        let tree = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"image_input":{"supported":true},"structured_outputs":{"supported":true},
         "effort":{"supported":true,"low":{"supported":true},"max":{"supported":false}}}
        """#.utf8))
        #expect(ModelCapabilities(tree) == ModelCapabilities(imageInput: true, lowEffort: true, strictTools: true))
        let none = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"image_input":{"supported":false},"effort":{"supported":false}}"#.utf8))
        #expect(ModelCapabilities(none) == ModelCapabilities(imageInput: false, lowEffort: false, strictTools: false))
        #expect(ModelCapabilities(nil) == .unknown)
    }
}
