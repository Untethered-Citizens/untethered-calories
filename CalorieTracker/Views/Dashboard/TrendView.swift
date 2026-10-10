import SwiftUI
import SwiftData
import Charts

/// Tab 5: intake against the weight trend on one time axis. Stays an honest empty state
/// until there are about three weeks of both (D47).
struct TrendView: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(DayClock.self) private var clock

    @Query(sort: \MealEntry.dayKey) private var entries: [MealEntry]
    @Query(sort: \DailySummary.dayKey) private var summaries: [DailySummary]
    @Query private var targetRows: [Targets]

    private let windowDays = 28
    @ScaledMetric(relativeTo: .caption2) private var axisWidth = 38.0

    var body: some View {
        NavigationStack {
            ScrollView {
                let totals = DayTotalsIndex.build(entries: entries, summaries: summaries)
                let series = weightSeries(totals)
                let gate = TrendGate(intakeDays: totals.values.filter { $0.entryCount > 0 }.count,
                                     readings: series.readings.count)
                VStack(alignment: .leading, spacing: 14) {
                    if gate.isUnlocked {
                        unlocked(totals, series)
                    } else {
                        locked(gate)
                    }
                }
                .padding(18)
                .foregroundStyle(Palette.ink)
            }
            .background(Palette.background)
            .navigationTitle("Trend")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func weightSeries(_ totals: [LocalDate: NutritionTotals]) -> WeightSeries {
        let readings = summaries.compactMap { row in row.weight.map { WeightReading(day: row.date, pounds: $0) } }
        let firstLogged = totals.filter { $0.value.entryCount > 0 }.keys.min()
        return WeightSeries(readings: readings, firstLoggingDay: firstLogged, today: clock.today)
    }

    // MARK: Locked

    private func locked(_ gate: TrendGate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs about three weeks")
                .font(.condensed(24))
            Text("This view lines up what you eat against your weight trend. Day-to-day weight swings hide real change, so it stays empty until there's enough of both to say something true.")
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(gate.intakeLine)
                Text(gate.weightLine)
            }
            .foregroundStyle(Palette.muted)
            HStack(spacing: 4) {
                ForEach(0..<TrendGate.intakeDaysNeeded, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < gate.intakeDays ? Palette.green : Palette.track)
                        .frame(height: 8)
                }
            }
            .padding(.top, 4)
            .accessibilityElement()
            .accessibilityLabel("\(min(gate.intakeDays, TrendGate.intakeDaysNeeded)) of \(TrendGate.intakeDaysNeeded) days logged")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: 6))
    }

    // MARK: Unlocked

    @ViewBuilder
    private func unlocked(_ totals: [LocalDate: NutritionTotals], _ series: WeightSeries) -> some View {
        let today = clock.today
        let start = max(today.adding(days: -(windowDays - 1)), series.span.first ?? today)
        let days = LocalDate.range(from: start, through: today)
        let target = TargetHistory.effective(on: today, in: targetRows.map(\.period)).calories
        let timeZone = AppSettings().timeZone
        let domain = start.date(in: timeZone).addingTimeInterval(-43_200)...today.date(in: timeZone).addingTimeInterval(43_200)

        Text("Last \(days.count) days")
            .font(.barlow(.subheadline, weight: .semibold))
            .foregroundStyle(Palette.muted)

        SectionHeading(title: "Calories")
        Chart {
            ForEach(days, id: \.self) { day in
                let total = totals[day] ?? .zero
                BarMark(x: .value("Day", day.date(in: timeZone), unit: .day),
                        y: .value("Calories", total.calories - total.estimatedCalories))
                    .foregroundStyle(Palette.green)
                    .opacity(day == today ? 0.5 : 1)
                BarMark(x: .value("Day", day.date(in: timeZone), unit: .day),
                        y: .value("Calories", total.estimatedCalories))
                    .foregroundStyle(SourceFill(source: .estimate))
                    .opacity(day == today ? 0.5 : 1)
            }
            RuleMark(y: .value("Target", target))
                .foregroundStyle(Palette.ink)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartXScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Palette.rule)
                AxisValueLabel { axisLabel(value) }
            }
        }
        .frame(height: 180)
        // Chart labels can't fit the largest sizes; the text around the chart scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("Daily calories against the \(target.formatted()) target")

        SectionHeading(title: "Weight, 7-day average")
        Chart {
            ForEach(series.readings.filter { $0.day >= start }, id: \.day) { reading in
                PointMark(x: .value("Day", reading.day.date(in: timeZone), unit: .day),
                          y: .value("Weight", unit.fromPounds(reading.pounds)))
                    .foregroundStyle(Palette.muted.opacity(0.6))
                    .symbolSize(20)
            }
            ForEach(Array(series.averageRuns.enumerated()), id: \.offset) { index, run in
                ForEach(run.filter { $0.day >= start }, id: \.day) { point in
                    LineMark(x: .value("Day", point.day.date(in: timeZone), unit: .day),
                             y: .value("Weight", unit.fromPounds(point.pounds)),
                             series: .value("Line", "average \(index)"))
                        .foregroundStyle(Palette.green)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Palette.rule)
                AxisValueLabel { axisLabel(value) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Palette.muted)
            }
        }
        .frame(height: 160)
        // Chart labels can't fit the largest sizes; the text around the chart scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("Weight readings and 7-day average")

        if let balance = EnergyBalance(series: series, dayTotals: totals, today: today) {
            balancePanel(balance)
        } else {
            Text("Not enough overlap yet between logged days and a steady weight average to compare them.")
                .font(.barlow(.subheadline)).foregroundStyle(Palette.muted)
        }
    }

    private var unit: WeightUnit { AppSettings().weightUnit }

    /// A fixed-width axis label, so both charts' plots start at the same x and days line up.
    private func axisLabel(_ value: AxisValue) -> some View {
        Group {
            if let number = value.as(Double.self) {
                Text(number.formatted(.number.precision(.fractionLength(0))))
            }
        }
        .font(.barlow(.caption2))
        .foregroundStyle(Palette.muted)
        .frame(width: axisWidth, alignment: .trailing)
    }

    private func balancePanel(_ balance: EnergyBalance) -> some View {
        let text = LogText()
        let range = "\(text.dayName(balance.from, template: "MMM d")) to \(text.dayName(balance.through, template: "MMM d"))"
        let change = unit.fromPounds(abs(balance.poundsChange)).formatted(.number.precision(.fractionLength(1)))
        let direction = balance.poundsChange < 0 ? "went down" : balance.poundsChange > 0 ? "went up" : "held steady"
        let gap = abs(balance.impliedDailyBalance).formatted()
        let side = balance.impliedDailyBalance < 0 ? "below" : "above"
        return VStack(alignment: .leading, spacing: 8) {
            Text("What the two say together").font(.barlow(.headline))
            Text("From \(range), you ate about \(balance.averageIntake.formatted()) calories a day, on the \(balance.loggedDays) days you logged. Your average weight \(direction)\(balance.poundsChange == 0 ? "" : " \(change) \(unit.rawValue)"). That suggests you ate about \(gap) a day \(side) what you used, which puts your maintenance near \(balance.estimatedMaintenance.formatted()) a day.")
            Text("A rough guide only: it assumes about 3,500 calories per pound, and missed logs, estimates and water shifts all move it.")
                .font(.barlow(.footnote)).foregroundStyle(Palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: 6))
        .padding(.top, 8)
    }
}
