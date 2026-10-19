import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

// Issue #28: nothing reaches the Messages API without a stored Allow. Model IDs are synthetic.

private func reply(_ blocks: String, stop: String) -> String {
    #"{"id":"msg_test","type":"message","role":"assistant","model":"claude-test","content":[\#(blocks)],"stop_reason":"\#(stop)","usage":{"input_tokens":10,"output_tokens":5}}"#
}

private let hello = reply(#"{"type":"text","text":"Which size?"}"#, stop: "end_turn")

/// Runs `onSend` as each request goes out, then replies like the stub.
private final class HookedTransport: HTTPTransport, @unchecked Sendable {
    let stub: StubTransport
    let onSend: () -> Void
    init(_ stub: StubTransport, onSend: @escaping () -> Void) { self.stub = stub; self.onSend = onSend }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        onSend()
        return try await stub.send(request)
    }
}

struct AIConsentStateTests {
    func fresh() -> AppSettings { AppSettings(defaults: UserDefaults(suiteName: "consent-\(UUID())")!) }

    @Test func unansweredByDefault() {
        #expect(fresh().aiConsent == .unanswered)
    }

    @Test func allowDeclineAndReset() {
        let s = fresh()
        s.allowAI()
        #expect(s.aiConsent == .allowed)
        s.declineAI() // the Settings switch turned off
        #expect(s.aiConsent == .declined)
        s.allowAI()
        s.resetAIConsent() // the key was removed
        #expect(s.aiConsent == .unanswered)
    }

    @Test func allowForAnOlderListMustBeAskedAgain() {
        #expect(AIConsent(answer: "allowed", version: AIConsent.currentVersion) == .allowed)
        #expect(AIConsent(answer: "allowed", version: AIConsent.currentVersion - 1) == .unanswered)
        #expect(AIConsent(answer: "declined", version: 0) == .declined)
        #expect(AIConsent(answer: nil, version: 0) == .unanswered)
        #expect(AIConsent(answer: "something else", version: AIConsent.currentVersion) == .unanswered)
    }
}

struct AnthropicClientConsentTests {
    let request = MessagesRequest(model: "claude-test", maxTokens: 10, system: "s", tools: [],
                                  messages: [.user([ContentBlock.text("hi")])], effort: nil)

    @Test func refusesByDefaultWithoutSending() async {
        let stub = StubTransport([.http(200, hello)])
        await #expect(throws: AnthropicError.noConsent) {
            try await AnthropicClient(apiKey: "sk-ant-test-key", transport: stub).createMessage(request)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func sendsWhenAllowed() async throws {
        let stub = StubTransport([.http(200, hello)])
        let client = AnthropicClient(apiKey: "sk-ant-test-key", transport: stub, mayCreateMessages: { true })
        _ = try await client.createMessage(request)
        #expect(stub.requests.count == 1)
    }

    @Test func listingModelsNeedsNoConsent() async throws {
        let stub = StubTransport([.http(200, #"{"data":[],"has_more":false,"last_id":null}"#)])
        _ = try await AnthropicClient(apiKey: "sk-ant-test-key", transport: stub).listModels()
        #expect(stub.requests.count == 1)
    }
}

@MainActor
struct LogConversationConsentTests {
    let container: ModelContainer
    let settings: AppSettings
    let clock = Date(timeIntervalSince1970: 1_790_710_200)

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
        settings = AppSettings(defaults: UserDefaults(suiteName: "LogConsent-\(UUID())")!)
        settings.modelID = "claude-test-model"
        settings.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    }

    func make(_ transport: HTTPTransport) -> LogConversation {
        let fixed = clock
        let conversation = LogConversation(context: container.mainContext, settings: settings,
                                           apiKey: { "sk-ant-test-key" }, transport: transport, now: { fixed })
        conversation.capabilities["claude-test-model"] = ModelCapabilities(imageInput: true, lowEffort: true, strictTools: true)
        return conversation
    }

    /// An existing install with a key but no answer: nothing goes out until asked.
    @Test func existingInstallWithNoAnswerSendsNothing() async {
        let stub = StubTransport([])
        let conversation = make(stub)
        let taken = await conversation.send("had a burrito")
        #expect(!taken)
        #expect(stub.requests.isEmpty)
        #expect(conversation.failure?.needsConsent == true)
        #expect(conversation.items.isEmpty)
    }

    @Test func declinedSendsNothing() async {
        settings.declineAI()
        let stub = StubTransport([])
        let conversation = make(stub)
        #expect(await conversation.send("had a burrito") == false)
        #expect(stub.requests.isEmpty)
    }

    @Test func allowedSends() async {
        settings.allowAI()
        let stub = StubTransport([.http(200, hello)])
        let conversation = make(stub)
        #expect(await conversation.send("had a burrito"))
        #expect(stub.requests.count == 1)
        #expect(stub.requests.first?.url?.path == "/v1/messages")
        #expect(conversation.failure == nil)
    }

    @Test func withdrawingStopsTheNextSend() async {
        settings.allowAI()
        let stub = StubTransport([.http(200, hello)])
        let conversation = make(stub)
        await conversation.send("had a burrito")
        settings.declineAI()
        #expect(await conversation.send("a large one") == false)
        #expect(stub.requests.count == 1)
        #expect(conversation.failure?.needsConsent == true)
    }

    /// Withdrawn while a reply is on its way: the tool round that would follow isn't sent.
    @Test func withdrawingMidReplyStopsTheNextRound() async {
        settings.allowAI()
        let toolReply = reply(#"{"type":"tool_use","id":"toolu_1","name":"get_day","input":{"date":"2026-09-28"}}"#, stop: "tool_use")
        let stub = StubTransport([.http(200, toolReply), .http(200, hello)])
        let settings = settings
        let conversation = make(HookedTransport(stub) { settings.declineAI() })
        await conversation.send("what did I eat yesterday?")
        #expect(stub.requests.count == 1)
        #expect(conversation.failure?.needsConsent == true)
    }

    /// "Calories left?" is answered on the phone, so it works without consent.
    @Test func localAnswerNeedsNoConsent() async {
        let stub = StubTransport([])
        let conversation = make(stub)
        #expect(await conversation.send("calories left?"))
        #expect(stub.requests.isEmpty)
    }
}
