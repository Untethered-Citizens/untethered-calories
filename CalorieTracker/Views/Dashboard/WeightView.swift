import SwiftUI
import SwiftData
import Charts

/// Tab 4: weight readings, with the 7-day average drawn only where a week holds enough
/// readings to mean something. Readings arrive from Apple Health.
struct WeightView: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(DayClock.self) private var clock
    @Environment(HealthWeight.self) private var health
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<DailySummary> { $0.weight != nil }, sort: \DailySummary.dayKey)
    private var weighed: [DailySummary]
    @Query(sort: \MealEntry.dayKey) private var entries: [MealEntry]
    @Query(filter: #Predicate<DailySummary> { $0.rolledUp }, sort: \DailySummary.dayKey)
    private var rolledUp: [DailySummary]

    @State private var addingWeight = false

    private var unit: WeightUnit { AppSettings().weightUnit }

    var body: some View {
        NavigationStack {
            Group {
                if weighed.isEmpty {
                    emptyState
                } else {
                    content(series)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background)
            .navigationTitle("Weight")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $addingWeight) {
                AddWeightView(latestPounds: weighed.last?.weight)
            }
        }
    }

    private var series: WeightSeries {
        let readings = weighed.compactMap { row in row.weight.map { WeightReading(day: row.date, pounds: $0) } }
        let firstLogged = [entries.first?.date, rolledUp.first?.date].compactMap { $0 }.min()
        return WeightSeries(readings: readings, firstLoggingDay: firstLogged, today: clock.today)
    }

    private func shown(_ pounds: Double) -> String {
        unit.fromPounds(pounds).formatted(.number.precision(.fractionLength(1)))
    }

    private var unitName: String { unit == .lb ? "pounds" : "kilograms" }

    // MARK: Content

    private func content(_ series: WeightSeries) -> some View {
        let text = LogText()
        return List {
            Group {
                if let latest = series.latest {
                    HeroNumber(value: shown(latest.pounds),
                               unit: "\(unitName)\n\(text.dayName(latest.day, template: "MMM d"))",
                               size: 88)
                }
                changeLine(series)
                if health.isAvailable {
                    Button("Add weight", systemImage: "plus") { addingWeight = true }
                        .buttonStyle(.bordered)
                        .tint(Palette.green)
                        .padding(.top, 8)
                }
                WeightChart(series: series, unit: unit)
                    .frame(height: 240)
                    // Chart labels can't fit the largest sizes; the text around the chart scales fully.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.vertical, 8)
                Text(note(series))
                    .font(.barlow(.subheadline))
                    .foregroundStyle(Palette.muted)
                SectionHeading(title: "Readings")
            }
            .dashboardRow()

            ForEach(series.readings.reversed(), id: \.day) { reading in
                HStack {
                    Text(text.dayName(reading.day))
                    Spacer()
                    Text(shown(reading.pounds)).font(.number(22, relativeTo: .title2))
                }
                .foregroundStyle(Palette.ink)
                .dashboardRow(separator: true)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func changeLine(_ series: WeightSeries) -> some View {
        let count = series.readings.count
        let since = series.first.map { LogText().dayName($0.day, template: "MMM d") } ?? ""
        let change = series.change ?? 0
        let amount = unit.fromPounds(abs(change)).formatted(.number.precision(.fractionLength(1)))
        let direction = change == 0 ? Text("No change")
            : Text("\(change > 0 ? "Up" : "Down") \(Text(amount).fontWeight(.semibold).foregroundStyle(Palette.ink)) \(unit.rawValue)")
        return Text("\(direction) since \(since), across \(count) \(count == 1 ? "reading" : "readings")")
            .foregroundStyle(Palette.muted)
    }

    private func note(_ series: WeightSeries) -> String {
        let pace = unit == .lb ? "about 1 lb a week" : "about 0.5 kg a week"
        if series.hasTrend {
            return "The green line is a 7-day average. Read that, not the dots. It's left out wherever a week has fewer than four readings. Goal pace is \(pace)."
        }
        return "Too few readings for a trend yet. The 7-day average appears once a week holds at least four readings. Until then, a pound either way is mostly water. Goal pace is \(pace)."
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No weight logged yet")
                .font(.condensed(24))
            if !health.isAvailable {
                Text("Weight comes from Apple Health, which isn't available on this device.")
                    .foregroundStyle(Palette.muted)
            } else if health.needsRequest {
                Text("Your weight lives in Apple Health, so readings from a smart scale and the ones you add here end up in the same place. Connect once, then add a weight here or just weigh in.\n\nWhen iOS asks, allow Weight for both reading and writing, and choose All Recorded Data to bring in your last 90 days. Steps are only for the Home Screen widget, so allow them if you want steps there.")
                    .foregroundStyle(Palette.muted)
                Button("Connect Apple Health") {
                    Task {
                        await health.connect(into: context, today: clock.today, timeZone: AppSettings().timeZone)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.green)
                .padding(.top, 4)
            } else {
                Text(HealthWeight.noReadingsHelp)
                    .foregroundStyle(Palette.muted)
                Button("Add weight") { addingWeight = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.green)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: 6))
        .padding(18)
    }
}

/// Readings as dots on a dashed line across the whole span (gaps visible), with the
/// 7-day average as a bold green line where it qualifies.
struct WeightChart: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    var series: WeightSeries
    var unit: WeightUnit

    private let timeZone = AppSettings().timeZone

    private var domain: ClosedRange<Double> {
        let values = series.readings.map { unit.fromPounds($0.pounds) }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max(1, (hi - lo) * 0.4)
        return (lo - pad).rounded(.down)...(hi + pad).rounded(.up)
    }

    var body: some View {
        let showLabels = series.readings.count <= 10
        Chart {
            ForEach(series.readings, id: \.day) { reading in
                LineMark(x: .value("Day", reading.day.date(in: timeZone), unit: .day),
                         y: .value("Weight", unit.fromPounds(reading.pounds)),
                         series: .value("Line", "readings"))
                    .foregroundStyle(Palette.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Day", reading.day.date(in: timeZone), unit: .day),
                          y: .value("Weight", unit.fromPounds(reading.pounds)))
                    .symbol {
                        Circle().strokeBorder(Palette.ink, lineWidth: 2)
                            .background(Circle().fill(Palette.panel))
                            .frame(width: 9, height: 9)
                    }
                    .annotation(position: .top) {
                        if showLabels {
                            Text(unit.fromPounds(reading.pounds).formatted(.number.precision(.fractionLength(1))))
                                .font(.number(12, relativeTo: nil)).foregroundStyle(Palette.ink)
                        }
                    }
            }
            ForEach(Array(series.averageRuns.enumerated()), id: \.offset) { index, run in
                ForEach(run, id: \.day) { point in
                    LineMark(x: .value("Day", point.day.date(in: timeZone), unit: .day),
                             y: .value("Weight", unit.fromPounds(point.pounds)),
                             series: .value("Line", "average \(index)"))
                        .foregroundStyle(Palette.green)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .chartXScale(domain: series.span.first!.date(in: timeZone)...series.span.last!.date(in: timeZone))
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Palette.rule)
                AxisValueLabel().foregroundStyle(Palette.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, series.span.count / 6))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Palette.muted)
            }
        }
        .accessibilityLabel("Weight readings and 7-day average")
    }
}
