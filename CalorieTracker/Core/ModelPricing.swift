import Foundation

/// Token counts for some stretch of use, as Anthropic reports them in `usage`.
struct TokenCounts: Equatable, Sendable {
    /// Input not read from or written to the cache.
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output,
                    cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }

    var total: Int { input + output + cacheWrite + cacheRead }
}

/// Prices per million tokens, for estimating what logging costs on the user's own key (D55).
///
/// Copied from Anthropic's pricing page (platform.claude.com/docs/en/about-claude/pricing) on the
/// date below. The bill in the Anthropic Console is the real figure; this is an estimate, and
/// a model that isn't listed gets token counts only, never a guessed price.
struct ModelPricing: Equatable, Sendable {
    static let asOf = LocalDate(year: 2026, month: 10, day: 22)!

    var input: Double
    var output: Double
    /// 5-minute cache writes, the duration the app uses.
    var cacheWrite: Double
    var cacheRead: Double

    /// Standard first-party API rates. Cache writes are 1.25x input for the 5-minute duration;
    /// cache reads are 0.1x input except where the page says otherwise. Haiku 5.5 charges more for
    /// prompts over 100,000 tokens; the app's prompts are a few thousand, so it uses the lower rate.
    static let table: [String: ModelPricing] = [
        "claude-fable-5-1": ModelPricing(input: 10, output: 50, cacheWrite: 12.50, cacheRead: 0.25),
        "claude-fable-5": ModelPricing(input: 10, output: 50, cacheWrite: 12.50, cacheRead: 1),
        "claude-opus-5-5": ModelPricing(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.20),
        "claude-opus-5": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50),
        "claude-opus-4-8": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50),
        "claude-opus-4-7": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50),
        "claude-opus-4-6": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50),
        "claude-opus-4-5": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50),
        "claude-sonnet-5-5": ModelPricing(input: 2, output: 10, cacheWrite: 2.50, cacheRead: 0.10),
        "claude-sonnet-5": ModelPricing(input: 2, output: 10, cacheWrite: 2.50, cacheRead: 0.20),
        "claude-sonnet-4-6": ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.30),
        "claude-sonnet-4-5": ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.30),
        "claude-haiku-5-5": ModelPricing(input: 0.10, output: 0.50, cacheWrite: 0.125, cacheRead: 0.01),
        "claude-haiku-4-5": ModelPricing(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.10),
    ]

    /// The price for a model ID, also matching a dated snapshot of a listed model
    /// ("claude-haiku-4-5-20251001"). Nil when the model isn't listed.
    static func forModel(_ id: String) -> ModelPricing? {
        if let exact = table[id] { return exact }
        let dated = table.keys.filter { key in
            guard id.hasPrefix(key + "-") else { return false }
            let rest = id.dropFirst(key.count + 1)
            return rest.count == 8 && rest.allSatisfy(\.isNumber)
        }
        return dated.max { $0.count < $1.count }.flatMap { table[$0] }
    }

    /// Estimated US dollars for these counts.
    func cost(of tokens: TokenCounts) -> Double {
        (Double(tokens.input) * input + Double(tokens.output) * output
            + Double(tokens.cacheWrite) * cacheWrite + Double(tokens.cacheRead) * cacheRead) / 1_000_000
    }
}

/// A stretch of use summed across models, with its estimated cost.
struct UsageSummary: Equatable, Sendable {
    var tokens = TokenCounts()
    var requests = 0
    var messages = 0
    /// Dollars for the models with a known price.
    var cost = 0.0
    /// Models used whose price isn't on file, so the cost leaves them out.
    var unpricedModels: Set<String> = []

    var averagePerMessage: Double? { messages > 0 ? cost / Double(messages) : nil }

    /// "$0.43", or "$0.012" for small amounts.
    static func dollars(_ amount: Double) -> String {
        let digits = amount < 1 ? 3 : 2
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(digits)))
    }
}
