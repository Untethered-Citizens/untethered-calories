import Foundation

/// One model from Anthropic's live model list (`GET /v1/models`).
struct AnthropicModel: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    /// RFC 3339 text, e.g. "2026-05-14T00:00:00Z". Same format for every model, so it sorts as text.
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

/// Why a call to Anthropic failed, in terms the UI can explain.
enum AnthropicError: Error, Equatable {
    /// 401: the key is wrong, revoked or deleted.
    case invalidKey
    /// 403: the key is real but can't do this (organization or workspace settings).
    case permissionDenied(String)
    /// The account is out of credit, has reached a spend limit, or has a payment problem (issue #29).
    /// Anthropic sends this as a 402, a 400 or a spend-cap 429; `error(status:data:headers:)` sorts them.
    case billing
    /// 429: too many requests. `retryAfter` is in seconds when the server says.
    case rateLimited(retryAfter: Int?)
    /// 500 and 529: Anthropic's side is having trouble. Worth retrying later.
    case serverBusy
    /// No connection, or the request timed out.
    case offline
    /// The user hasn't allowed sending to Anthropic (issue #28). Nothing was sent.
    case noConsent
    /// Anything else, with Anthropic's message when there is one.
    case other(status: Int, message: String)

    /// A plain sentence for the user.
    var userMessage: String {
        switch self {
        case .invalidKey: "Anthropic didn't accept this key. Check that you copied all of it, and that it hasn't been deleted in the Console."
        case .permissionDenied(let detail): "This key isn't allowed to do that. \(detail)"
        case .billing: "Your Anthropic account is out of credit or has reached its spend limit. Add credit or raise the limit in the Anthropic Console, then try again."
        case .rateLimited: "Anthropic is limiting requests right now. Try again in a minute."
        case .serverBusy: "Anthropic is busy right now. Try again in a minute."
        case .offline: "You're offline, so the key couldn't be checked."
        case .noConsent: "Sharing with Anthropic is off, so nothing was sent."
        case .other(let status, let message): "Something went wrong (\(status)). \(message)"
        }
    }
}

/// Sends a request. The app uses URLSession; tests use a stub.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Direct calls to the Anthropic API with the user's own key. There is no server of ours in between.
/// The key goes only in the `x-api-key` header and is never logged.
struct AnthropicClient: Sendable {
    static let baseURL = URL(string: "https://api.anthropic.com/v1/")!
    static let apiVersion = "2023-06-01"

    let apiKey: String
    var transport: HTTPTransport = URLSessionTransport()
    /// Asked before every Messages API call (issue #28). Off unless the caller passes the
    /// stored consent, so a new call site can't send food data without asking. Listing
    /// models only checks the key and isn't gated.
    var mayCreateMessages: @Sendable () -> Bool = { false }

    /// The models this key can use, newest first. This also checks the key:
    /// listing models is free (no tokens), and a bad key gets `.invalidKey`.
    func listModels() async throws -> [AnthropicModel] {
        var models: [AnthropicModel] = []
        var afterID: String?
        repeat {
            var components = URLComponents(url: Self.baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]
            if let afterID { components.queryItems?.append(URLQueryItem(name: "after_id", value: afterID)) }
            let page: ModelPage = try await get(components.url!)
            models += page.data
            afterID = page.hasMore ? page.lastID : nil
        } while afterID != nil
        return models.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Plumbing

    private struct ModelPage: Decodable {
        let data: [AnthropicModel]
        let hasMore: Bool
        let lastID: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case lastID = "last_id"
        }
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let type: String
            let message: String
            let details: Extra?
        }
        struct Extra: Decodable { let error_code: String? }
        let error: Detail
    }

    func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        try await send(request(url))
    }

    /// Sends a request and decodes the reply, turning failures into `AnthropicError`.
    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError {
            throw Self.isOffline(error) ? AnthropicError.offline : AnthropicError.other(status: 0, message: error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw Self.error(status: response.statusCode, data: data, headers: response)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AnthropicError.other(status: response.statusCode, message: "Anthropic's reply wasn't in the expected shape.")
        }
    }

    static func error(status: Int, data: Data, headers: HTTPURLResponse) -> AnthropicError {
        let body = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
        let message = body?.message ?? ""
        if isBilling(status: status, message: message, code: body?.details?.error_code) { return .billing }
        switch status {
        case 401: return .invalidKey
        case 403: return .permissionDenied(message)
        case 429: return .rateLimited(retryAfter: headers.value(forHTTPHeaderField: "retry-after").flatMap(Int.init))
        case 500, 502, 503, 504, 529: return .serverBusy
        default: return .other(status: status, message: message)
        }
    }

    /// Billing problems, matched loosely on Anthropic's wording so small rewordings still match:
    /// - 402 `billing_error`.
    /// - 400 when credit runs out ("Your credit balance is too low…") or a spend limit the user set is
    ///   reached ("You have reached your specified API usage limits", or "…workspace API usage limits").
    /// - 429 with `enforced_spend_limit_reached`: the usage tier's monthly cap. Retrying won't help until it resets.
    static func isBilling(status: Int, message: String, code: String?) -> Bool {
        switch status {
        case 402:
            return true
        case 400:
            let text = message.lowercased()
            return ["credit balance", "usage limit", "spend limit"].contains { text.contains($0) }
        case 429:
            return code == "enforced_spend_limit_reached"
        default:
            return false
        }
    }

    private static func isOffline(_ error: URLError) -> Bool {
        [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
         .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }
}

enum ModelRecommendation {
    /// The recommended model: the newest Sonnet in the live list (D19). Sonnet has held up well on
    /// descriptions, nutrition labels and meal photos, at a moderate cost per entry.
    /// Chosen by rule, not by a hard-coded ID, so it stays current as new models ship.
    static func recommended(in models: [AnthropicModel]) -> AnthropicModel? {
        models.filter { $0.id.hasPrefix("claude-sonnet") }.max { $0.createdAt < $1.createdAt }
    }

    /// The family in an ID like "claude-sonnet-5-5" ("sonnet"). Nil if the ID doesn't follow that shape.
    static func family(of id: String) -> String? {
        let parts = id.split(separator: "-")
        guard parts.count >= 3, parts[0] == "claude", parts[1].allSatisfy(\.isLetter) else { return nil }
        return String(parts[1])
    }

    /// The current generation: the newest model in each family, newest first.
    /// Models whose ID doesn't name a family are treated as current, so nothing unfamiliar is hidden.
    static func current(in models: [AnthropicModel]) -> [AnthropicModel] {
        var newestByFamily: [String: AnthropicModel] = [:]
        var unfamiliar: [AnthropicModel] = []
        for model in models {
            guard let family = family(of: model.id) else { unfamiliar.append(model); continue }
            if let seen = newestByFamily[family], seen.createdAt >= model.createdAt { continue }
            newestByFamily[family] = model
        }
        return (Array(newestByFamily.values) + unfamiliar).sorted { $0.createdAt > $1.createdAt }
    }

    /// The model to use after a list refresh: keep the user's choice while it's still offered,
    /// otherwise fall back to the recommendation.
    static func resolve(current: String?, in models: [AnthropicModel]) -> String? {
        if let current, models.contains(where: { $0.id == current }) { return current }
        return recommended(in: models)?.id ?? models.first?.id
    }
}
