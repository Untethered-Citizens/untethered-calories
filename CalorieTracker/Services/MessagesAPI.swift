import Foundation

/// One message in the conversation sent to Anthropic. Content blocks are kept as raw JSON
/// so the assistant's blocks (including thinking blocks) go back exactly as received.
struct APIMessage: Codable, Equatable, Sendable {
    var role: String
    var content: [JSONValue]

    static func user(_ content: [JSONValue]) -> APIMessage { APIMessage(role: "user", content: content) }
}

enum ContentBlock {
    static func text(_ text: String) -> JSONValue { ["type": "text", "text": .string(text)] }

    static func jpeg(_ data: Data) -> JSONValue {
        ["type": "image",
         "source": ["type": "base64", "media_type": "image/jpeg", "data": .string(data.base64EncodedString())]]
    }

    static func toolResult(id: String, text: String, isError: Bool) -> JSONValue {
        var block: [String: JSONValue] = ["type": "tool_result", "tool_use_id": .string(id), "content": .string(text)]
        if isError { block["is_error"] = true }
        return .object(block)
    }
}

/// A `tool_use` block from the model.
struct ToolCall: Equatable, Sendable {
    var id: String
    var name: String
    var input: JSONValue
}

/// What the model sent back.
struct MessageResponse: Decodable, Sendable {
    let id: String
    let content: [JSONValue]
    let stopReason: String?
    let usage: Usage?

    struct Usage: Decodable, Equatable, Sendable {
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationInputTokens: Int?
        var cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, content, usage
        case stopReason = "stop_reason"
    }

    /// The visible text, joined. Thinking blocks are never shown.
    var text: String {
        content.filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var toolCalls: [ToolCall] {
        content.compactMap { block in
            guard block["type"]?.stringValue == "tool_use",
                  let id = block["id"]?.stringValue, let name = block["name"]?.stringValue else { return nil }
            return ToolCall(id: id, name: name, input: block["input"] ?? [:])
        }
    }
}

/// What a model can do, from the live model list. Every field defaults to the safe
/// choice when Anthropic doesn't say.
struct ModelCapabilities: Equatable, Sendable {
    var imageInput = true
    var lowEffort = false
    var strictTools = false

    static let unknown = ModelCapabilities()

    init(imageInput: Bool = true, lowEffort: Bool = false, strictTools: Bool = false) {
        self.imageInput = imageInput
        self.lowEffort = lowEffort
        self.strictTools = strictTools
    }

    /// Reads the `capabilities` tree, e.g. `{"effort": {"supported": true, "low": {"supported": true}}}`.
    init(_ tree: JSONValue?) {
        func supported(_ path: String...) -> Bool? {
            var node = tree
            for key in path { node = node?[key] }
            if case .bool(let value) = node?["supported"] { return value }
            return nil
        }
        imageInput = supported("image_input") ?? true
        lowEffort = (supported("effort") ?? false) && (supported("effort", "low") ?? false)
        strictTools = supported("structured_outputs") ?? false
    }
}

/// The request body for `POST /v1/messages`.
struct MessagesRequest: Encodable, Sendable {
    var model: String
    var maxTokens: Int
    var system: String
    var tools: [JSONValue]
    var messages: [APIMessage]
    /// "low" keeps logging quick and cheap. Sent only when the model supports it.
    var effort: String?

    enum CodingKeys: String, CodingKey {
        case model, system, tools, messages
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
        case cacheControl = "cache_control"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        // The breakpoint on the system prompt caches the tools and the prompt together.
        let systemBlock: JSONValue = ["type": "text", "text": .string(system), "cache_control": ["type": "ephemeral"]]
        try container.encode([systemBlock], forKey: .system)
        try container.encode(tools, forKey: .tools)
        try container.encode(messages, forKey: .messages)
        // Top-level caching also caches the conversation so far, so a photo isn't paid for
        // in full on every follow-up turn.
        try container.encode(["type": "ephemeral"] as JSONValue, forKey: .cacheControl)
        if let effort { try container.encode(["effort": .string(effort)] as JSONValue, forKey: .outputConfig) }
    }

    /// Stable bytes: sorted keys, so the cached prefix is identical from one request to the next.
    func body() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension AnthropicClient {
    /// One call to the Messages API. Errors come back as `AnthropicError`.
    func createMessage(_ body: MessagesRequest) async throws -> MessageResponse {
        var request = request(Self.baseURL.appending(path: "messages"), method: "POST")
        request.timeoutInterval = 90 // photos and a busy server can take a while
        request.httpBody = try body.body()
        return try await send(request)
    }

    /// One model's details, including what it can do. Free, like the model list.
    func capabilities(of modelID: String) async throws -> ModelCapabilities {
        struct Details: Decodable { let capabilities: JSONValue? }
        let details: Details = try await send(request(Self.baseURL.appending(path: "models/\(modelID)")))
        return ModelCapabilities(details.capabilities)
    }
}
