import Foundation
import SwiftData

/// Tokens used on one day with one model (D55). Only counts: never the text sent or received.
@Model
final class TokenUsage {
    #Index<TokenUsage>([\.dayKey])

    var dayKey: String
    var modelID: String
    var requests: Int
    /// User messages that reached Anthropic. One message can take several requests (tool rounds).
    var messages: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheWriteTokens: Int
    var cacheReadTokens: Int

    init(day: LocalDate, modelID: String) {
        dayKey = day.iso
        self.modelID = modelID
        requests = 0
        messages = 0
        inputTokens = 0
        outputTokens = 0
        cacheWriteTokens = 0
        cacheReadTokens = 0
    }

    var date: LocalDate { LocalDate(iso: dayKey)! }

    var tokens: TokenCounts {
        TokenCounts(input: inputTokens, output: outputTokens, cacheWrite: cacheWriteTokens, cacheRead: cacheReadTokens)
    }
}

enum UsageLedger {
    /// Adds one reply's usage to the day's row for that model.
    static func record(_ usage: MessageResponse.Usage, model: String, newMessage: Bool,
                       on day: LocalDate, in context: ModelContext) throws {
        let key = day.iso
        var descriptor = FetchDescriptor<TokenUsage>(predicate: #Predicate { $0.dayKey == key && $0.modelID == model })
        descriptor.fetchLimit = 1
        let row: TokenUsage
        if let existing = try context.fetch(descriptor).first {
            row = existing
        } else {
            row = TokenUsage(day: day, modelID: model)
            context.insert(row)
        }
        row.requests += 1
        if newMessage { row.messages += 1 }
        row.inputTokens += usage.inputTokens
        row.outputTokens += usage.outputTokens
        row.cacheWriteTokens += usage.cacheCreationInputTokens ?? 0
        row.cacheReadTokens += usage.cacheReadInputTokens ?? 0
        try context.save()
    }

    /// Sums rows from `start` through `end` (both optional) and prices them.
    static func summary(of rows: [TokenUsage], from start: LocalDate? = nil, through end: LocalDate? = nil) -> UsageSummary {
        var result = UsageSummary()
        for row in rows {
            if let start, row.date < start { continue }
            if let end, row.date > end { continue }
            result.tokens = result.tokens + row.tokens
            result.requests += row.requests
            result.messages += row.messages
            if let price = ModelPricing.forModel(row.modelID) {
                result.cost += price.cost(of: row.tokens)
            } else {
                result.unpricedModels.insert(row.modelID)
            }
        }
        return result
    }
}
