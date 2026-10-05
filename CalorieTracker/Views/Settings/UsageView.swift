import SwiftUI
import SwiftData

/// Settings → Usage and cost: what logging has used on the user's own API key (D55).
struct UsageView: View {
    @Query(sort: \TokenUsage.dayKey) private var rows: [TokenUsage]

    private var today: LocalDate { LocalDate.today(in: AppSettings().timeZone) }

    private var periods: [(title: String, summary: UsageSummary)] {
        let monthStart = LocalDate(year: today.year, month: today.month, day: 1)!
        let lastMonthStart = monthStart.adding(days: -1)
        let lastMonthFirst = LocalDate(year: lastMonthStart.year, month: lastMonthStart.month, day: 1)!
        return [
            ("This month", UsageLedger.summary(of: rows, from: monthStart)),
            ("Last month", UsageLedger.summary(of: rows, from: lastMonthFirst, through: monthStart.adding(days: -1))),
            ("All time", UsageLedger.summary(of: rows)),
        ]
    }

    var body: some View {
        List {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView("Nothing used yet", systemImage: "gauge.with.dots.needle.0percent",
                                           description: Text("Once you log by conversation, the tokens used and an estimated cost appear here."))
                } else {
                    ForEach(periods, id: \.title) { period in
                        Section(period.title) { rows(for: period.summary) }
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("An estimate from the token counts Anthropic reports and its published prices on \(LogText().dayName(ModelPricing.asOf, template: "MMM d, yyyy")). Your actual bill is in the Anthropic Console. Answers worked out on the phone, like \"calories left?\", cost nothing.")
                }
            }
            .listRowBackground(Palette.panel)
        }
        .themedBackground()
        .navigationTitle("Usage and cost")
    }

    @ViewBuilder
    private func rows(for summary: UsageSummary) -> some View {
        if summary.requests == 0 {
            Text("No use").foregroundStyle(.secondary)
        } else {
            LabeledContent("Estimated cost", value: UsageSummary.dollars(summary.cost))
            LabeledContent("Messages", value: summary.messages.formatted())
            if let average = summary.averagePerMessage {
                LabeledContent("Per message", value: UsageSummary.dollars(average))
            }
            LabeledContent("Tokens", value: summary.tokens.total.formatted())
            LabeledContent("Read from cache", value: cacheShare(summary.tokens))
            if !summary.unpricedModels.isEmpty {
                Text("No price on file for \(summary.unpricedModels.sorted().joined(separator: ", ")), so it's left out of the cost.")
                    .font(.barlow(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Share of input served from the cache, which is billed at a fraction of the price.
    private func cacheShare(_ tokens: TokenCounts) -> String {
        let input = tokens.input + tokens.cacheWrite + tokens.cacheRead
        guard input > 0 else { return "–" }
        return (Double(tokens.cacheRead) / Double(input)).formatted(.percent.precision(.fractionLength(0)))
    }
}
