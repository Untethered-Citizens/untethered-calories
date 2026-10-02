import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

// Canned Messages API replies. Model IDs and tool IDs are synthetic.

private func reply(_ blocks: [String], stop: String) -> String {
    #"{"id":"msg_test","type":"message","role":"assistant","model":"claude-test","content":[\#(blocks.joined(separator: ","))],"stop_reason":"\#(stop)","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0}}"#
}

private func text(_ value: String) -> String { #"{"type":"text","text":"\#(value)"}"# }

private func toolUse(_ id: String, _ name: String, _ input: String) -> String {
    #"{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}"#
}

private func entry(date: String = "2026-09-29", meal: String = "Snack", description: String = "Protein bar",
                   calories: Int, protein: Int, carbs: Int, fat: Int, source: String = "Label",
                   alcohol: Bool = false, basis: String = "stated_numbers", usual: String = "") -> String {
    #"{"date":"\#(date)","meal":"\#(meal)","description":"\#(description)","calories":\#(calories),"protein":\#(protein),"carbs":\#(carbs),"fat":\#(fat),"source":"\#(source)","contains_alcohol":\#(alcohol),"basis":"\#(basis)","usual_meal_name":"\#(usual)"}"#
}

private func entries(_ items: String...) -> String { #"{"entries":[\#(items.joined(separator: ","))]}"# }

/// The JSON body of a sent request.
private func body(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func messages(_ request: URLRequest) throws -> [[String: Any]] {
    let sent = try body(request)
    return try #require(sent["messages"] as? [[String: Any]])
}

private func blocks(_ message: [String: Any]) -> [[String: Any]] {
    message["content"] as? [[String: Any]] ?? []
}

@MainActor
struct LogConversationTests {
    let container: ModelContainer
    let settings: AppSettings
    let modelID = "claude-test-model"
    /// 2026-09-29 12:30 in Los Angeles.
    var clock = Date(timeIntervalSince1970: 1_790_710_200)

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
        settings = AppSettings(defaults: UserDefaults(suiteName: "LogConversationTests-\(UUID())")!)
        settings.modelID = modelID
        settings.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    }

    var context: ModelContext { container.mainContext }

    func make(_ stub: StubTransport, key: String? = "sk-ant-test-key", now: (() -> Date)? = nil) -> LogConversation {
        let fixed = clock
        let conversation = LogConversation(context: context, settings: settings, apiKey: { key },
                                           transport: stub, now: now ?? { fixed })
        conversation.capabilities[modelID] = ModelCapabilities(imageInput: true, lowEffort: true, strictTools: true)
        return conversation
    }

    func storedEntries() throws -> [MealEntry] { try context.fetch(FetchDescriptor<MealEntry>()) }

    @Test func clockIsMiddayInLosAngeles() {
        #expect(LogContext.dateTime(clock, settings.timeZone) == "2026-09-29 Tuesday 12:30")
    }

    // MARK: Request shape

    @Test func requestCachesPromptAndCarriesContextInUserMessage() async throws {
        let stub = StubTransport([.http(200, reply([text("Which size?")], stop: "end_turn"))])
        let conversation = make(stub)
        await conversation.send("had a burrito")

        let request = try #require(stub.requests.first)
        #expect(request.url?.path == "/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test-key")
        let sent = try body(request)
        #expect(sent["model"] as? String == modelID)
        let system = try #require(sent["system"] as? [[String: Any]])
        #expect(system.count == 1)
        #expect(system[0]["text"] as? String == SystemPrompt.text) // frozen: no dates or totals in it
        #expect((system[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect((sent["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect((sent["output_config"] as? [String: String])?["effort"] == "low")
        let tools = try #require(sent["tools"] as? [[String: Any]])
        #expect(tools.map { $0["name"] as? String } == LogTool.allCases.map(\.rawValue))
        #expect(tools.allSatisfy { $0["strict"] as? Bool == true })

        let first = try blocks(messages(request)[0])
        #expect((first[0]["text"] as? String)?.hasPrefix("<app_context>") == true)
        #expect((first[0]["text"] as? String)?.contains("Remaining today: 1785 kcal") == true)
        #expect((first[0]["text"] as? String)?.contains("Default meal now: Lunch") == true) // 12:30
        #expect(first.last?["text"] as? String == "had a burrito")
        #expect(conversation.items.count == 2) // the user's bubble and the question
    }

    @Test func plainRequestWhenModelCapabilitiesAreUnknown() async throws {
        let stub = StubTransport([.http(200, reply([text("Hi")], stop: "end_turn"))])
        let conversation = make(stub)
        conversation.capabilities[modelID] = .unknown
        await conversation.send("hello")
        let sent = try body(try #require(stub.requests.first))
        #expect(sent["output_config"] == nil)
        let tools = try #require(sent["tools"] as? [[String: Any]])
        #expect(tools.allSatisfy { $0["strict"] == nil })
    }

    // MARK: Path A

    @Test func pathAWritesImmediatelyWithOneCall() async throws {
        let stub = StubTransport([
            .http(200, reply([text("Check: 80+120+99=299."),
                              toolUse("toolu_1", "log_entries", entries(entry(calories: 300, protein: 20, carbs: 30, fat: 11)))], stop: "tool_use")),
            .http(200, reply([text("Enjoy.")], stop: "end_turn")),
        ])
        let conversation = make(stub)
        await conversation.send("300 cal protein bar, 20p 30c 11f")
        // Words alongside a direct log are dropped: the app's confirmation says it all.
        #expect(!conversation.items.contains { if case .assistant = $0.kind { true } else { false } })

        #expect(stub.requests.count == 1) // no second call just to say "logged"
        let stored = try storedEntries()
        #expect(stored.count == 1)
        #expect(stored.first?.source == .label)
        #expect(stored.first?.dayKey == "2026-09-29")
        guard case .logged(let line) = conversation.items.last?.kind else {
            Issue.record("Expected a confirmation line"); return
        }
        #expect(line.contains("snack — Protein bar"))
        #expect(line.contains("(label)"))
        #expect(conversation.revision == 1)

        // The deferred tool result leads the next message, and history is append-only.
        await conversation.send("thanks")
        #expect(stub.requests.count == 2)
        let firstMessages = try messages(stub.requests[0])
        let secondMessages = try messages(stub.requests[1])
        #expect(secondMessages.count == 3)
        #expect(NSArray(array: Array(secondMessages.prefix(1))).isEqual(to: firstMessages))
        let next = blocks(secondMessages[2])
        #expect(next[0]["type"] as? String == "tool_result")
        #expect(next[0]["tool_use_id"] as? String == "toolu_1")
        #expect((next[1]["text"] as? String)?.contains("Eaten today: 300 kcal") == true)
    }

    @Test func rejectedWriteGoesBackToTheModelToFix() async throws {
        // Macros rotated across fields: 4×10 + 4×20 + 9×55 = 615, far from 480.
        let bad = entries(entry(description: "Salad kit", calories: 480, protein: 10, carbs: 20, fat: 55))
        let fixed = entries(entry(description: "Salad kit", calories: 480, protein: 20, carbs: 55, fat: 21))
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "log_entries", bad)], stop: "tool_use")),
            .http(200, reply([toolUse("toolu_2", "log_entries", fixed)], stop: "tool_use")),
        ])
        let conversation = make(stub)
        await conversation.send("salad kit 480 cal, 20 protein, 55 carbs, 21 fat")

        #expect(stub.requests.count == 2)
        let result = blocks(try messages(stub.requests[1]).last!)[0]
        #expect(result["is_error"] as? Bool == true)
        #expect((result["content"] as? String)?.contains("= 615 kcal") == true)
        let stored = try storedEntries()
        #expect(stored.count == 1)
        #expect(stored.first?.fat == 21)
    }

    @Test func exactUsualMealUsesStoredNumbersAndSource() async throws {
        context.insert(UsualMeal(name: "Usual breakfast", triggerPhrases: ["my normal breakfast"], meal: .breakfast,
                                 description: "Yogurt with granola", calories: 330, protein: 17, carbs: 26, fat: 19,
                                 source: .estimate))
        // The model sends made-up numbers and the wrong source; the stored meal wins.
        let input = entries(entry(meal: "Breakfast", description: "usual", calories: 999, protein: 1, carbs: 1, fat: 1,
                                  source: "Label", basis: "usual_meal", usual: "my normal breakfast"))
        let stub = StubTransport([.http(200, reply([toolUse("toolu_1", "log_entries", input)], stop: "tool_use"))])
        await make(stub).send("my normal breakfast")

        let stored = try #require(try storedEntries().first)
        #expect(stored.calories == 330)
        #expect(stored.foodDescription == "Yogurt with granola")
        #expect(stored.source == .estimate) // an estimate stays an estimate
    }

    @Test func labelPhotoWithoutAPhotoIsRefused() async throws {
        let input = entries(entry(calories: 300, protein: 20, carbs: 30, fat: 11, basis: "label_photo"))
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "log_entries", input)], stop: "tool_use")),
            .http(200, reply([text("Please send the photo.")], stop: "end_turn")),
        ])
        await make(stub).send("logged from the label")
        #expect(try storedEntries().isEmpty)
        let result = blocks(try messages(stub.requests[1]).last!)[0]
        #expect((result["content"] as? String)?.contains("needs a photo") == true)
    }

    @Test func futureDatesAreRefused() async throws {
        let input = entries(entry(date: "2026-09-30", calories: 300, protein: 20, carbs: 30, fat: 11))
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "log_entries", input)], stop: "tool_use")),
            .http(200, reply([text("Fixed.")], stop: "end_turn")),
        ])
        await make(stub).send("bar")
        #expect(try storedEntries().isEmpty)
    }

    // MARK: Path B

    @Test func estimateWaitsForAcceptThenLogs() async throws {
        let input = entries(entry(meal: "Lunch", description: "BLT with avocado", calories: 765, protein: 30,
                                  carbs: 60, fat: 45, source: "Estimate", basis: "description"))
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "propose_estimate", input)], stop: "tool_use")),
            .http(200, reply([text("Noted.")], stop: "end_turn")),
        ])
        let conversation = make(stub)
        await conversation.send("BLT with avocado for lunch")

        #expect(stub.requests.count == 1)
        #expect(try storedEntries().isEmpty) // nothing until the tap
        guard case .proposal(let id) = conversation.items.last?.kind else {
            Issue.record("Expected a card"); return
        }
        #expect(conversation.proposals[id]?.status == .pending)

        conversation.accept(id)
        let stored = try #require(try storedEntries().first)
        #expect(stored.source == .estimate)
        #expect(stored.calories == 765)
        guard case .done(let line) = conversation.proposals[id]?.status else {
            Issue.record("Expected the card to be done"); return
        }
        #expect(line.contains("lunch — BLT with avocado"))
        #expect(line.contains("(estimate)"))

        conversation.accept(id) // a second tap does nothing
        #expect(try storedEntries().count == 1)

        // The model hears the outcome in the next message.
        await conversation.send("thanks")
        let next = blocks(try messages(stub.requests[1]).last!)
        #expect(next[0]["tool_use_id"] as? String == "toolu_1")
        #expect((next[1]["text"] as? String)?.contains("accepted your estimate") == true)
    }

    @Test func editedEstimateIsCheckedAndStaysAnEstimate() async throws {
        let input = entries(entry(meal: "Dinner", description: "Pasta", calories: 600, protein: 20, carbs: 90,
                                  fat: 18, source: "Estimate", basis: "description"))
        let stub = StubTransport([.http(200, reply([toolUse("toolu_1", "propose_estimate", input)], stop: "tool_use"))])
        let conversation = make(stub)
        await conversation.send("pasta")
        guard case .proposal(let id) = conversation.items.last?.kind,
              case .estimate(let pending) = conversation.proposals[id]?.kind else {
            Issue.record("Expected an estimate card"); return
        }

        var bad = pending[0].draft
        bad.calories = 300 // macros still add to 602
        #expect(throws: WriteRejected.self) { try conversation.acceptEdited(id, drafts: [bad]) }
        #expect(try storedEntries().isEmpty)

        var good = pending[0].draft
        good.description = "Pasta, half portion"
        good.calories = 300
        good.protein = 10
        good.carbs = 45
        good.fat = 9
        try conversation.acceptEdited(id, drafts: [good])
        let stored = try #require(try storedEntries().first)
        #expect(stored.calories == 300)
        #expect(stored.source == .estimate)
    }

    @Test func foodPhotoIsSentAndMustBeAPhotoEstimate() async throws {
        let asLabel = entries(entry(meal: "Dinner", description: "Curry", calories: 500, protein: 20, carbs: 60,
                                    fat: 20, source: "Label", basis: "food_photo"))
        let honest = entries(entry(meal: "Dinner", description: "Curry", calories: 500, protein: 20, carbs: 60,
                                   fat: 20, source: "Photo Estimate", basis: "food_photo"))
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "propose_estimate", asLabel)], stop: "tool_use")),
            .http(200, reply([toolUse("toolu_2", "propose_estimate", honest)], stop: "tool_use")),
        ])
        let conversation = make(stub)
        await conversation.send("", photos: [Data([0xFF, 0xD8, 0xFF])])

        let first = blocks(try messages(stub.requests[0])[0])
        #expect(first.contains { $0["type"] as? String == "image" })
        #expect(stub.requests.count == 2)
        let rejection = blocks(try messages(stub.requests[1]).last!)[0]
        #expect((rejection["content"] as? String)?.contains("Photo Estimate") == true)
        guard case .proposal(let id) = conversation.items.last?.kind else {
            Issue.record("Expected a card"); return
        }
        conversation.accept(id)
        #expect(try storedEntries().first?.source == .photoEstimate)
    }

    @Test func dismissedCardWritesNothingAndIsReported() async throws {
        let input = entries(entry(description: "Cookie", calories: 200, protein: 2, carbs: 28, fat: 9,
                                  source: "Estimate", basis: "description"))
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "propose_estimate", input)], stop: "tool_use")),
            .http(200, reply([text("OK.")], stop: "end_turn")),
        ])
        let conversation = make(stub)
        await conversation.send("a cookie")
        guard case .proposal(let id) = conversation.items.last?.kind else { Issue.record("No card"); return }
        conversation.dismiss(id)
        conversation.accept(id)
        #expect(try storedEntries().isEmpty)
        await conversation.send("never mind")
        let next = blocks(try messages(stub.requests[1]).last!)
        #expect((next[1]["text"] as? String)?.contains("dismissed") == true)
    }

    // MARK: Other tools

    @Test func readToolsContinueTheLoop() async throws {
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "get_day", #"{"date":"2026-09-27"}"#)], stop: "tool_use")),
            .http(200, reply([text("Nothing logged on Sunday.")], stop: "end_turn")),
        ])
        let conversation = make(stub)
        await conversation.send("what did I eat Sunday?")
        #expect(stub.requests.count == 2)
        let result = blocks(try messages(stub.requests[1]).last!)[0]
        #expect((result["content"] as? String)?.contains("No food logged") == true)
        #expect(result["is_error"] == nil)
        guard case .assistant(let answer) = conversation.items.last?.kind else { Issue.record("No answer"); return }
        #expect(answer == "Nothing logged on Sunday.")
    }

    @Test func rangeSummaryLeavesOutGapsAndToday() throws {
        for (day, calories) in [("2026-09-26", 1800), ("2026-09-28", 1600), ("2026-09-29", 500)] {
            let draft = EntryDraft(date: LocalDate(iso: day)!, meal: .lunch, description: "Food", calories: calories,
                                   protein: calories / 16, carbs: calories / 8, fat: calories / 36, source: .label)
            try EntryWriter.commit([PendingEntry(draft: draft, origin: .statedNumbers)], confirmedByUser: false, in: context)
        }
        let runner = ToolRunner(context: context, today: LocalDate(iso: "2026-09-29")!, conversationHasPhoto: false)
        let outcome = runner.run(ToolCall(id: "t", name: "get_range_summary",
                                          input: try JSONDecoder().decode(JSONValue.self, from: Data(#"{"from":"2026-09-25","to":"2026-09-29"}"#.utf8))))
        #expect(!outcome.isError)
        #expect(outcome.text.contains("2026-09-27: no data"))
        #expect(outcome.text.contains("(today, partial)"))
        #expect(outcome.text.contains("Average over 2 complete days"))
        #expect(outcome.text.contains("1700 kcal"))
        #expect(outcome.text.contains("Days with no data: 2."))
    }

    @Test func targetsCardAppliesFromItsDate() async throws {
        let past = #"{"calories":1900,"protein":150,"carbs":180,"fat":65,"effective_from":"2026-09-01","goal_note":""}"#
        let ok = #"{"calories":1900,"protein":150,"carbs":180,"fat":65,"effective_from":"2026-09-29","goal_note":"maintain"}"#
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "propose_targets", past)], stop: "tool_use")),
            .http(200, reply([toolUse("toolu_2", "propose_targets", ok)], stop: "tool_use")),
        ])
        let conversation = make(stub)
        await conversation.send("set my calories to 1900")
        let rejection = blocks(try messages(stub.requests[1]).last!)[0]
        #expect((rejection["content"] as? String)?.contains("can't be in the past") == true)
        guard case .proposal(let id) = conversation.items.last?.kind else { Issue.record("No card"); return }
        #expect(try TargetStore.current(on: LocalDate(iso: "2026-09-29")!, in: context) == .defaults)
        conversation.accept(id)
        #expect(try TargetStore.current(on: LocalDate(iso: "2026-09-29")!, in: context).calories == 1900)
    }

    @Test func usualMealCardSavesTheMeal() async throws {
        let input = #"{"name":"Usual lunch","trigger_phrases":["my normal lunch"],"meal":"Lunch","description":"Frozen curry","calories":470,"protein":14,"carbs":66,"fat":19,"source":"Label","contains_alcohol":false}"#
        let stub = StubTransport([.http(200, reply([toolUse("toolu_1", "add_usual_meal", input)], stop: "tool_use"))])
        let conversation = make(stub)
        await conversation.send("save that as my usual lunch")
        guard case .proposal(let id) = conversation.items.last?.kind else { Issue.record("No card"); return }
        #expect(try context.fetch(FetchDescriptor<UsualMeal>()).isEmpty)
        conversation.accept(id)
        let saved = try #require(try context.fetch(FetchDescriptor<UsualMeal>()).first)
        #expect(saved.name == "Usual lunch")
        #expect(saved.triggerPhrases == ["my normal lunch"])
        #expect(conversation.logContext().render().contains("\"Usual lunch\" (also: \"my normal lunch\")"))
    }

    // MARK: Local answers, errors, lifecycle

    @Test func remainingQuestionIsAnsweredLocallyEvenWithoutAKey() async throws {
        let stub = StubTransport([])
        let conversation = make(stub, key: nil)
        #expect(await conversation.send("calories left?"))
        #expect(stub.requests.isEmpty)
        guard case .local(let answer) = conversation.items.last?.kind else { Issue.record("No local answer"); return }
        #expect(answer.contains("cal left today"))
    }

    @Test func noKeyKeepsTheMessage() async {
        let conversation = make(StubTransport([]), key: nil)
        #expect(await conversation.send("a banana") == false)
        #expect(conversation.failure?.needsKey == true)
        #expect(conversation.items.isEmpty)
    }

    @Test func offlineKeepsTheMessageForRetry() async throws {
        let stub = StubTransport([
            .failure(URLError(.notConnectedToInternet)),
            .http(200, reply([text("Which size?")], stop: "end_turn")),
        ])
        let conversation = make(stub)
        await conversation.send("a banana")
        #expect(conversation.failure?.canRetry == true)
        await conversation.retry()
        #expect(conversation.failure == nil)
        #expect(NSArray(array: try messages(stub.requests[1])).isEqual(to: try messages(stub.requests[0])))
    }

    @Test func rejectedKeyPointsToSettings() async {
        let stub = StubTransport([.http(401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)])
        let conversation = make(stub)
        await conversation.send("a banana")
        #expect(conversation.failure?.needsKey == true)
    }

    @Test func idleConversationStartsAfresh() async throws {
        var now = clock
        let stub = StubTransport([
            .http(200, reply([text("Which size?")], stop: "end_turn")),
            .http(200, reply([text("Which size?")], stop: "end_turn")),
        ])
        let conversation = make(stub, now: { now })
        await conversation.send("a banana")
        now = clock.addingTimeInterval(31 * 60)
        await conversation.send("an apple")
        #expect(try messages(stub.requests[1]).count == 1)
        #expect(conversation.items.contains { if case .newConversation = $0.kind { true } else { false } })
    }

    @Test func cutOffToolCallIsAnsweredNextTime() async throws {
        let stub = StubTransport([
            .http(200, reply([toolUse("toolu_1", "get_day", #"{"date":"2026-09-29"}"#)], stop: "max_tokens")),
            .http(200, reply([text("OK")], stop: "end_turn")),
        ])
        let conversation = make(stub)
        await conversation.send("what did I have today?")
        #expect(stub.requests.count == 1)
        await conversation.send("try again")
        let next = blocks(try messages(stub.requests[1]).last!)
        #expect(next[0]["tool_use_id"] as? String == "toolu_1")
        #expect(next[0]["is_error"] as? Bool == true)
    }

    @Test func thinkingBlocksGoBackUnchanged() async throws {
        let thinking = #"{"type":"thinking","thinking":"","signature":"sig-abc"}"#
        let stub = StubTransport([
            .http(200, reply([thinking, text("Which size?")], stop: "end_turn")),
            .http(200, reply([text("Logged?")], stop: "end_turn")),
        ])
        let conversation = make(stub)
        await conversation.send("a banana")
        await conversation.send("medium")
        let assistant = blocks(try messages(stub.requests[1])[1])
        #expect(assistant[0]["type"] as? String == "thinking")
        #expect(assistant[0]["signature"] as? String == "sig-abc")
        #expect(assistant[0]["thinking"] as? String == "")
    }
}

/// The chat kept between launches (D53).
@MainActor
struct ChatKeepingTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: ChatStore
    let modelID = "claude-test-model"
    /// 2026-09-29 12:30 in Los Angeles.
    let clock = Date(timeIntervalSince1970: 1_790_710_200)

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
        settings = AppSettings(defaults: UserDefaults(suiteName: "ChatKeepingTests-\(UUID())")!)
        settings.modelID = modelID
        settings.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        store = ChatStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID()).json"))
    }

    func launch(_ stub: StubTransport, at time: Date? = nil) -> LogConversation {
        let now = time ?? clock
        let conversation = LogConversation(context: container.mainContext, settings: settings, apiKey: { "sk-ant-test-key" },
                                           transport: stub, now: { now }, store: store)
        conversation.capabilities[modelID] = ModelCapabilities(imageInput: true, lowEffort: true, strictTools: true)
        return conversation
    }

    @Test func pendingCardStillWorksAfterRelaunch() async throws {
        let input = entries(entry(meal: "Lunch", description: "BLT", calories: 765, protein: 30,
                                  carbs: 60, fat: 45, source: "Estimate", basis: "description"))
        let first = launch(StubTransport([.http(200, reply([toolUse("toolu_1", "propose_estimate", input)], stop: "tool_use"))]))
        await first.send("BLT for lunch")
        guard case .proposal(let id) = first.items.last?.kind else { Issue.record("Expected a card"); return }

        let second = launch(StubTransport([]))
        #expect(second.proposals[id]?.status == .pending)
        second.accept(id)
        let saved = try container.mainContext.fetch(FetchDescriptor<MealEntry>())
        #expect(saved.map(\.foodDescription) == ["BLT"])
        #expect(saved.first?.source == .estimate)
    }

    @Test func relaunchStartsAFreshConversationBelowADivider() async throws {
        let first = launch(StubTransport([.http(200, reply([text("Hi.")], stop: "end_turn"))]))
        await first.send("hello")

        let stub = StubTransport([.http(200, reply([text("Sure.")], stop: "end_turn"))])
        let second = launch(stub)
        guard case .newConversation = second.items.last?.kind else { Issue.record("Expected a divider"); return }
        await second.send("and again")
        // Only the new message goes to Anthropic, never the restored chat.
        #expect(try messages(stub.requests[0]).count == 1)
    }

    @Test func photosAreNeverKept() async throws {
        let first = launch(StubTransport([.http(200, reply([text("Looks like soup.")], stop: "end_turn"))]))
        await first.send("what's this", photos: [Data([0xFF, 0xD8, 0xFF, 0x00])])

        let raw = try String(contentsOf: try #require(store.url), encoding: .utf8)
        #expect(!raw.contains("/9j/")) // no base64 JPEG in the file
        let second = launch(StubTransport([]))
        guard case .user(let text, let photos, let notKept) = second.items.first?.kind else {
            Issue.record("Expected the user's message"); return
        }
        #expect(text == "what's this")
        #expect(photos.isEmpty)
        #expect(notKept == 1)
    }

    @Test func chatPastTheRetentionWindowIsGone() async throws {
        settings.transcriptRetentionDays = 7
        let first = launch(StubTransport([.http(200, reply([text("Hi.")], stop: "end_turn"))]))
        await first.send("hello")

        let eightDaysLater = launch(StubTransport([]), at: clock.addingTimeInterval(8 * 86_400))
        #expect(eightDaysLater.items.isEmpty)
    }
}
