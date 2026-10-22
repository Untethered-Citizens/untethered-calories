import Foundation
import SwiftData
import Testing
@testable import CalorieTracker

struct ModelPricingTests {
    @Test func pricesEachTokenKindAtItsOwnRate() throws {
        let sonnet = try #require(ModelPricing.forModel("claude-sonnet-5-5"))
        // 1M each: $2 input + $10 output + $2.50 cache write + $0.10 cache read.
        let million = TokenCounts(input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000)
        #expect(abs(sonnet.cost(of: million) - 14.60) < 0.000_001)
    }

    @Test func cacheReadRatesDifferByModel() throws {
        #expect(ModelPricing.forModel("claude-opus-5-5")?.cacheRead == 0.20)   // 0.05x of $4
        #expect(ModelPricing.forModel("claude-sonnet-5-5")?.cacheRead == 0.10) // 0.05x of $2
        #expect(ModelPricing.forModel("claude-fable-5-1")?.cacheRead == 0.25)  // 0.025x of $10
        #expect(ModelPricing.forModel("claude-haiku-4-5")?.cacheRead == 0.10)  // 0.1x of $1
    }

    @Test func pricesHaiku55AtTheUpTo100kRate() throws {
        let haiku = try #require(ModelPricing.forModel("claude-haiku-5-5"))
        // 1M each: $0.10 input + $0.50 output + $0.125 cache write + $0.01 cache read.
        let million = TokenCounts(input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000)
        #expect(abs(haiku.cost(of: million) - 0.735) < 0.000_001)
    }

    @Test func pricesTheOlderModelsStillInThePicker() {
        #expect(ModelPricing.forModel("claude-opus-4-5")?.input == 5)
        #expect(ModelPricing.forModel("claude-sonnet-4-5")?.input == 3)
    }

    @Test func matchesADatedSnapshotButNotAnotherModel() {
        #expect(ModelPricing.forModel("claude-haiku-4-5-20251001") == ModelPricing.forModel("claude-haiku-4-5"))
        // "claude-opus-5-5" must not fall back to "claude-opus-5".
        #expect(ModelPricing.forModel("claude-opus-5-5")?.input == 4)
        #expect(ModelPricing.forModel("claude-opus-5-9") == nil)
        #expect(ModelPricing.forModel("claude-test-model") == nil)
    }

    @Test func smallAmountsShowThreeDecimals() {
        #expect(UsageSummary.dollars(0.0123) == "$0.012")
        #expect(UsageSummary.dollars(4.567) == "$4.57")
    }
}

@MainActor
struct UsageLedgerTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let day = LocalDate(iso: "2026-10-02")!

    init() throws {
        container = try DataStore.makeContainer(inMemory: true)
    }

    func usage(_ input: Int, _ output: Int, write: Int = 0, read: Int = 0) -> MessageResponse.Usage {
        MessageResponse.Usage(inputTokens: input, outputTokens: output, cacheCreationInputTokens: write, cacheReadInputTokens: read)
    }

    func rows() throws -> [TokenUsage] { try context.fetch(FetchDescriptor<TokenUsage>()) }

    @Test func sumsRequestsIntoOneRowPerDayAndModel() throws {
        try UsageLedger.record(usage(100, 50, write: 4000), model: "claude-sonnet-5-5", newMessage: true, on: day, in: context)
        try UsageLedger.record(usage(80, 20, read: 4000), model: "claude-sonnet-5-5", newMessage: false, on: day, in: context)
        try UsageLedger.record(usage(90, 30, read: 4000), model: "claude-sonnet-5-5", newMessage: true, on: day.adding(days: 1), in: context)
        let all = try rows()
        #expect(all.count == 2)
        let first = try #require(all.first { $0.dayKey == day.iso })
        #expect(first.requests == 2)
        #expect(first.messages == 1)
        #expect(first.tokens == TokenCounts(input: 180, output: 70, cacheWrite: 4000, cacheRead: 4000))
    }

    @Test func summaryFiltersByDateAndAveragesPerMessage() throws {
        try UsageLedger.record(usage(1_000_000, 0), model: "claude-sonnet-5-5", newMessage: true, on: day, in: context)
        try UsageLedger.record(usage(1_000_000, 0), model: "claude-sonnet-5-5", newMessage: true, on: day.adding(days: -40), in: context)
        let recent = UsageLedger.summary(of: try rows(), from: day.adding(days: -30))
        #expect(recent.messages == 1)
        #expect(abs(recent.cost - 2.0) < 0.000_001)
        let all = UsageLedger.summary(of: try rows())
        #expect(abs((all.averagePerMessage ?? 0) - 2.0) < 0.000_001)
    }

    @Test func unknownModelIsCountedButNotPriced() throws {
        try UsageLedger.record(usage(500, 100), model: "claude-future-9", newMessage: true, on: day, in: context)
        let summary = UsageLedger.summary(of: try rows())
        #expect(summary.cost == 0)
        #expect(summary.tokens.total == 600)
        #expect(summary.unpricedModels == ["claude-future-9"])
    }
}
