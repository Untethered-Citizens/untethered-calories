import SwiftUI
import SwiftData
import Charts

/// Tab 3: seven days of calories, label vs estimate, against the target. Tap a day for its
/// detail. Pages back through older weeks, using daily totals once meal detail is gone.
struct WeekView: View {
    @Environment(DayClock.self) private var clock
    /// 0 is the week ending today; 1 the seven days before that, and so on.
    @State private var weeksBack = 0

    var body: some View {
        NavigationStack {
            let end = clock.today.adding(days: -7 * weeksBack)
            WeekContent(today: clock.today, end: end, weeksBack: $weeksBack)
                .id("\(clock.today.iso)-\(weeksBack)")
                .navigationTitle("Week")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WeekContent: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    let today: LocalDate
    let end: LocalDate
    @Binding var weeksBack: Int

    @Query private var entries: [MealEntry]
    @Query private var summaries: [DailySummary]
    @Query private var targetRows: [Targets]
    @Query private var firstEntry: [MealEntry]
    @Query private var firstSummary: [DailySummary]

    @State private var selected: LocalDate?
    @State private var editing: MealEntry?
    @State private var deleting: MealEntry?

    init(today: LocalDate, end: LocalDate, weeksBack: Binding<Int>) {
        self.today = today
        self.end = end
        _weeksBack = weeksBack
        let lo = end.adding(days: -6).iso, hi = end.iso
        _entries = Query(filter: #Predicate<MealEntry> { $0.dayKey >= lo && $0.dayKey <= hi })
        _summaries = Query(filter: #Predicate<DailySummary> { $0.dayKey >= lo && $0.dayKey <= hi })
        var oldestEntry = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.dayKey)])
        oldestEntry.fetchLimit = 1
        _firstEntry = Query(oldestEntry)
        var oldestSummary = FetchDescriptor<DailySummary>(predicate: #Predicate { $0.rolledUp },
                                                          sortBy: [SortDescriptor(\.dayKey)])
        oldestSummary.fetchLimit = 1
        _firstSummary = Query(oldestSummary)
    }

    private var periods: [TargetPeriod] { targetRows.map(\.period) }
    private var dayTotals: [LocalDate: NutritionTotals] { DayTotalsIndex.build(entries: entries, summaries: summaries) }
    private var firstLoggingDay: LocalDate? { (firstEntry.map(\.date) + firstSummary.map(\.date)).min() }

    var body: some View {
        let totals = dayTotals
        let stats = WeekStats(today: today, ending: end, dayTotals: totals, targetPeriods: periods,
                              firstLoggingDay: firstLoggingDay)
        let shown = selected ?? defaultDay(stats)
        List {
            Group {
                pager(stats)
                WeekChart(days: stats.days, totals: totals, today: today,
                          target: TargetHistory.effective(on: end, in: periods).calories,
                          targetFor: { TargetHistory.effective(on: $0, in: periods).calories },
                          selected: shown, onSelect: { selected = $0 })
                    .frame(height: 260)
                    // Seven day labels can't fit large text; the day details below scale fully,
                    // and VoiceOver reads every day's value.
                    .dynamicTypeSize(...DynamicTypeSize.large)
                dayHeader(shown, totals[shown])
            }
            .dashboardRow()

            dayDetail(shown, totals[shown])

            Group {
                statsRow(stats)
                SectionHeading(title: "Average macros")
                MacroBars(protein: stats.averageProtein ?? 0, carbs: stats.averageCarbs ?? 0,
                          fat: stats.averageFat ?? 0, targets: TargetHistory.effective(on: end, in: periods))
                Text(stats.honestyNote())
                    .font(.barlow(.subheadline))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 8)
            }
            .dashboardRow()
        }
        .listStyle(.plain)
        .entryActions(editing: $editing, deleting: $deleting)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    /// Opens on the most recent complete day, not today.
    private func defaultDay(_ stats: WeekStats) -> LocalDate {
        stats.completeDays.last ?? stats.days.last!
    }

    // MARK: Pager

    private func pager(_ stats: WeekStats) -> some View {
        let text = LogText()
        let canGoBack = firstLoggingDay.map { $0 < stats.days.first! } ?? false
        return HStack {
            Button("Earlier week", systemImage: "chevron.left") { weeksBack += 1 }
                .disabled(!canGoBack)
            Spacer()
            Text("\(text.dayName(stats.days.first!, template: "MMM d")) – \(text.dayName(stats.days.last!, template: "MMM d"))")
                .font(.barlow(.headline))
            Spacer()
            Button("Later week", systemImage: "chevron.right") { weeksBack -= 1 }
                .disabled(weeksBack == 0)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.ink)
        .tint(Palette.green)
    }

    // MARK: Drill-down

    private func dayHeader(_ day: LocalDate, _ totals: NutritionTotals?) -> some View {
        let target = TargetHistory.effective(on: day, in: periods)
        return VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Palette.rule).padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline) {
                Text(LogText().dayName(day))
                    .font(.condensed(26))
                Spacer()
                if let totals, totals.entryCount > 0 {
                    (Text(totals.calories.formatted()).font(.number(26, weight: .bold, relativeTo: .title2))
                     + Text(" / \(target.calories.formatted())").font(.barlow(.subheadline)).foregroundStyle(Palette.muted))
                }
            }
            .foregroundStyle(Palette.ink)
            Text(daySubline(day, totals, target: target.calories))
                .font(.barlow(.subheadline))
                .foregroundStyle(Palette.muted)
            if let totals, totals.entryCount > 0 {
                MacroBars(protein: Double(totals.protein), carbs: Double(totals.carbs),
                          fat: Double(totals.fat), targets: target)
                    .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func daySubline(_ day: LocalDate, _ totals: NutritionTotals?, target: Int) -> String {
        guard let totals, totals.entryCount > 0 else { return "Nothing was logged this day." }
        let diff = totals.calories - target
        var parts = [diff > 0 ? "\(diff.formatted()) over target" : "\((-diff).formatted()) under target",
                     "\(totals.entryCount) \(totals.entryCount == 1 ? "entry" : "entries")",
                     "\(totals.estimatedPercent ?? 0)% estimated"]
        if day == today { parts.insert("Day in progress", at: 0) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func dayDetail(_ day: LocalDate, _ totals: NutritionTotals?) -> some View {
        let detail = entries.filter { $0.date == day }.sorted(by: MealEntry.detailOrder)
        let summary = summaries.first { $0.date == day && $0.rolledUp }
        if let summary, !summary.mealsDetail.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(summary.mealsDetail.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    Text(line).font(.barlow(.subheadline)).foregroundStyle(Palette.ink)
                }
                Text("Older days are kept as a summary, so their meals can't be edited.")
                    .font(.barlow(.footnote)).foregroundStyle(Palette.muted)
            }
            .dashboardRow()
        }
        if !detail.isEmpty || summary == nil {
            MealsSection(entries: detail, empty: "", editing: $editing, deleting: $deleting)
        }
    }

    // MARK: Stats

    private func statsRow(_ stats: WeekStats) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            statPanel(stats.averageCalories.map { $0.formatted() } ?? "–", "average a day")
            statPanel(stats.completeDays.isEmpty ? "–" : "\(stats.daysOverTarget) of \(stats.completeDays.count)",
                      "days over target")
            statPanel(stats.estimatedPercent.map { "\($0)%" } ?? "–", "of calories estimated")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 10)
    }

    private func statPanel(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.number(30, weight: .bold, relativeTo: .title1)).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.barlow(.footnote)).foregroundStyle(Palette.muted)
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Palette.panel, in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

/// Seven stacked bars: solid label calories under hatched estimated calories, a dashed
/// target line, and a value above each bar (plum when over, except today).
struct WeekChart: View {
    /// Redraws when the text size changes, so scaled numbers follow it.
    @Environment(\.dynamicTypeSize) private var typeSize
    var days: [LocalDate]
    var totals: [LocalDate: NutritionTotals]
    var today: LocalDate
    var target: Int
    var targetFor: (LocalDate) -> Int
    var selected: LocalDate
    var onSelect: (LocalDate) -> Void

    private var maxValue: Int {
        max(Int(Double(target) * 1.4), days.map { totals[$0]?.calories ?? 0 }.max() ?? 0)
    }

    var body: some View {
        Chart {
            RectangleMark(x: .value("Day", selected.iso), yStart: .value("Calories", 0),
                          yEnd: .value("Calories", maxValue))
                .foregroundStyle(Palette.ink.opacity(0.06))
            ForEach(days, id: \.self) { day in
                let total = totals[day] ?? .zero
                let label = total.calories - total.estimatedCalories
                let partial = day == today
                if total.entryCount == 0 {
                    BarMark(x: .value("Day", day.iso), y: .value("Calories", 0))
                        .annotation(position: .top) {
                            Text("no data").font(.barlow(.caption2)).foregroundStyle(Palette.muted)
                        }
                } else {
                    BarMark(x: .value("Day", day.iso), y: .value("Calories", label))
                        .foregroundStyle(Palette.green)
                        .opacity(partial ? 0.5 : 1)
                    BarMark(x: .value("Day", day.iso), y: .value("Calories", total.estimatedCalories))
                        .foregroundStyle(SourceFill(source: .estimate))
                        .opacity(partial ? 0.5 : 1)
                        .annotation(position: .top) {
                            let over = !partial && total.calories > targetFor(day)
                            Text(total.calories.formatted())
                                .font(.number(14, relativeTo: nil))
                                .foregroundStyle(over ? Palette.plum : Palette.ink)
                        }
                }
            }
            RuleMark(y: .value("Target", target))
                .foregroundStyle(Palette.ink)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartXScale(domain: days.map(\.iso)) // date order, whatever is drawn first
        .chartYScale(domain: 0...maxValue)
        .chartYAxis {
            // The target's label sits outside the plot, clear of the bar values.
            AxisMarks(position: .trailing, values: [target]) { _ in
                AxisValueLabel {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("target")
                        Text(target.formatted()).monospacedDigit()
                    }
                    .font(.barlow(.caption2))
                    .foregroundStyle(Palette.muted)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: days.map(\.iso)) { value in
                AxisValueLabel {
                    if let iso = value.as(String.self), let day = LocalDate(iso: iso) {
                        Text(LogText().dayName(day, template: "EEE d") + (day == today ? " ·" : ""))
                            .font(.barlow(.caption))
                            .fontWeight(day == selected ? .semibold : .regular)
                            .foregroundStyle(day == selected ? Palette.ink : Palette.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geometry[plot].origin.x
                        if let iso: String = proxy.value(atX: x), let day = LocalDate(iso: iso) { onSelect(day) }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories per day against the \(target.formatted()) target")
        .accessibilityValue(spokenDay(selected))
        .accessibilityHint("Swipe up or down to choose a day.")
        .accessibilityAdjustableAction { direction in
            // The chart picks a day by tap, which VoiceOver can't do, so swiping steps through them.
            guard let index = days.firstIndex(of: selected) else { return }
            switch direction {
            case .increment: if index + 1 < days.count { onSelect(days[index + 1]) }
            case .decrement: if index > 0 { onSelect(days[index - 1]) }
            @unknown default: break
            }
        }
    }

    private func spokenDay(_ day: LocalDate) -> String {
        let name = LogText().dayName(day)
        guard let total = totals[day], total.entryCount > 0 else { return "\(name), nothing logged" }
        var parts = ["\(name), \(total.calories.formatted()) calories of \(targetFor(day).formatted())"]
        if total.estimatedCalories > 0 {
            parts.append("\(total.estimatedCalories.formatted()) estimated")
        }
        if day == today { parts.append("today so far") }
        return parts.joined(separator: ", ")
    }
}
