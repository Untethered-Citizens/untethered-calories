import Foundation
import Testing
@testable import CalorieTracker

/// A fake network: returns canned responses in order and records the requests it saw.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    enum Reply { case http(Int, String, [String: String] = [:]), failure(URLError) }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch replies.removeFirst() {
        case .failure(let error):
            throw error
        case .http(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (Data(body.utf8), response)
        }
    }
}

/// Synthetic model IDs, so no test depends on which real models exist today.
private func model(_ id: String, _ created: String) -> String {
    #"{"type":"model","id":"\#(id)","display_name":"\#(id.uppercased())","created_at":"\#(created)T00:00:00Z"}"#
}

private func page(_ models: [String], hasMore: Bool = false, lastID: String? = nil) -> String {
    let last = lastID.map { #""\#($0)""# } ?? "null"
    return #"{"data":[\#(models.joined(separator: ","))],"has_more":\#(hasMore),"first_id":null,"last_id":\#(last)}"#
}

struct AnthropicClientTests {
    let fakeKey = "sk-ant-test-0000000000000000000000WXYZ"

    @Test func listsModelsNewestFirstWithHeaders() async throws {
        let stub = StubTransport([.http(200, page([model("claude-old", "2025-01-01"), model("claude-new", "2026-06-01")]))])
        let models = try await AnthropicClient(apiKey: fakeKey, transport: stub).listModels()
        #expect(models.map(\.id) == ["claude-new", "claude-old"])
        #expect(models.first?.displayName == "CLAUDE-NEW")

        let sent = try #require(stub.requests.first)
        #expect(sent.url?.path == "/v1/models")
        #expect(sent.value(forHTTPHeaderField: "x-api-key") == fakeKey)
        #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(sent.url?.absoluteString.contains(fakeKey) == false) // the key never goes in the URL
    }

    @Test func followsPages() async throws {
        let stub = StubTransport([
            .http(200, page([model("a", "2026-01-01")], hasMore: true, lastID: "a")),
            .http(200, page([model("b", "2025-01-01")])),
        ])
        let models = try await AnthropicClient(apiKey: fakeKey, transport: stub).listModels()
        #expect(models.map(\.id) == ["a", "b"])
        #expect(stub.requests.last?.url?.query?.contains("after_id=a") == true)
    }

    @Test(arguments: [
        (401, AnthropicError.invalidKey),
        (402, AnthropicError.billing),
        (403, AnthropicError.permissionDenied("Out of credit")),
        (429, AnthropicError.rateLimited(retryAfter: 20)),
        (500, AnthropicError.serverBusy),
        (529, AnthropicError.serverBusy),
        (404, AnthropicError.other(status: 404, message: "Out of credit")),
    ])
    func mapsHTTPErrors(status: Int, expected: AnthropicError) async {
        let body = #"{"type":"error","error":{"type":"x","message":"Out of credit"}}"#
        let stub = StubTransport([.http(status, body, ["retry-after": "20"])])
        await #expect(throws: expected) {
            try await AnthropicClient(apiKey: fakeKey, transport: stub).listModels()
        }
    }

    /// Anthropic's billing wording (issue #29), from platform.claude.com/docs/en/api/errors and /rate-limits.
    @Test(arguments: [
        (400, "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.", nil),
        (400, "You have reached your specified API usage limits. You will regain access on 2026-11-01 at 00:00 UTC.", nil),
        (400, "You have reached your specified workspace API usage limits. You will regain access on 2026-11-01 at 00:00 UTC.", nil),
        (429, "You have reached your API usage limits: your organization has crossed its monthly API usage threshold.", "enforced_spend_limit_reached"),
    ] as [(Int, String, String?)])
    func mapsBillingErrors(status: Int, message: String, code: String?) async {
        let details = code.map { #","details":{"error_code":"\#($0)"}"# } ?? ""
        let body = #"{"type":"error","error":{"type":"x","message":"\#(message)"\#(details)}}"#
        let stub = StubTransport([.http(status, body)])
        await #expect(throws: AnthropicError.billing) {
            try await AnthropicClient(apiKey: fakeKey, transport: stub).listModels()
        }
    }

    @Test func otherBadRequestsAndRateLimitsAreNotBilling() {
        #expect(!AnthropicClient.isBilling(status: 400, message: "messages: field required", code: nil))
        #expect(!AnthropicClient.isBilling(status: 429, message: "Number of request tokens has exceeded your per-minute rate limit", code: nil))
        #expect(!AnthropicClient.isBilling(status: 500, message: "credit balance", code: nil))
    }

    @MainActor @Test func billingMessageIsPlainAndRetryable() {
        let failure = LogConversation.failure(for: AnthropicError.billing)
        #expect(failure.canRetry)
        #expect(failure.message.contains("out of credit or has reached its spend limit"))
        #expect(!failure.message.contains("new conversation"))
    }

    @Test func offlineIsItsOwnError() async {
        let stub = StubTransport([.failure(URLError(.notConnectedToInternet))])
        await #expect(throws: AnthropicError.offline) {
            try await AnthropicClient(apiKey: fakeKey, transport: stub).listModels()
        }
    }

    @Test func errorMessagesNeverContainTheKey() {
        let all: [AnthropicError] = [.invalidKey, .billing, .permissionDenied("p"), .rateLimited(retryAfter: nil),
                                     .serverBusy, .offline, .other(status: 418, message: "m")]
        #expect(all.allSatisfy { !$0.userMessage.contains("sk-ant") })
    }
}

struct ModelRecommendationTests {
    let models = [
        AnthropicModel(id: "claude-opus-9", displayName: "Opus 9", createdAt: "2026-09-01T00:00:00Z"),
        AnthropicModel(id: "claude-sonnet-8", displayName: "Sonnet 8", createdAt: "2026-05-01T00:00:00Z"),
        AnthropicModel(id: "claude-sonnet-9", displayName: "Sonnet 9", createdAt: "2026-08-01T00:00:00Z"),
        AnthropicModel(id: "claude-haiku-9", displayName: "Haiku 9", createdAt: "2026-09-15T00:00:00Z"),
    ]

    @Test func recommendsTheNewestSonnet() {
        #expect(ModelRecommendation.recommended(in: models)?.id == "claude-sonnet-9")
        #expect(ModelRecommendation.recommended(in: models.filter { !$0.id.contains("sonnet") }) == nil)
    }

    @Test func familyComesFromTheID() {
        #expect(ModelRecommendation.family(of: "claude-sonnet-9") == "sonnet")
        #expect(ModelRecommendation.family(of: "claude-haiku-4-5-20251001") == "haiku")
        #expect(ModelRecommendation.family(of: "claude-3-haiku-20240307") == nil)
        #expect(ModelRecommendation.family(of: "something-else") == nil)
    }

    @Test func currentGenerationIsNewestPerFamily() {
        let odd = AnthropicModel(id: "claude-3-haiku-20240307", displayName: "Old", createdAt: "2024-03-07T00:00:00Z")
        let current = ModelRecommendation.current(in: models + [odd])
        #expect(current.map(\.id) == ["claude-haiku-9", "claude-opus-9", "claude-sonnet-9", "claude-3-haiku-20240307"])
        #expect(!current.contains { $0.id == "claude-sonnet-8" })
    }

    @Test func keepsTheUsersChoiceWhileItIsOffered() {
        #expect(ModelRecommendation.resolve(current: "claude-opus-9", in: models) == "claude-opus-9")
        #expect(ModelRecommendation.resolve(current: "claude-retired", in: models) == "claude-sonnet-9")
        #expect(ModelRecommendation.resolve(current: nil, in: models) == "claude-sonnet-9")
        #expect(ModelRecommendation.resolve(current: nil, in: []) == nil)
    }
}
