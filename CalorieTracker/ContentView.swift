import OSLog
import SwiftUI
import SwiftData

/// The home screen: five tabs, Log first (D45). Reopens on the last tab used.
struct ContentView: View {
    enum TabID: String {
        case log, today, week, weight, trend
    }

    @AppStorage("selectedTab") private var selected = TabID.log
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var clock = DayClock()
    @State private var health = HealthWeight()
    @State private var retentionDue = 0

    var body: some View {
        TabView(selection: $selected) {
            Tab("Log", systemImage: "bubble.left.and.text.bubble.right", value: TabID.log) { LogView() }
            Tab("Today", systemImage: "sun.max", value: TabID.today) { TodayView() }
            Tab("Week", systemImage: "chart.bar", value: TabID.week) { WeekView() }
            Tab("Weight", systemImage: "scalemass", value: TabID.weight) { WeightView() }
            Tab("Trend", systemImage: "chart.line.uptrend.xyaxis", value: TabID.trend) { TrendView() }
        }
        .tint(Palette.green)
        .environment(clock)
        .environment(health)
        .sheet(isPresented: Binding(get: { retentionDue > 0 }, set: { if !$0 { retentionDue = 0 } })) {
            if let keep = AppSettings().summaryRetentionDays {
                RetentionPromptView(dueCount: retentionDue, keepDays: keep, today: clock.today)
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await refresh() }
        }
    }

    private static let log = Logger(subsystem: "com.frees321.calorietracker", category: "maintenance")

    /// On launch, every return to the foreground and at midnight: fold meal detail older than
    /// the window into daily summaries (D51), bring in weight from Health, then check for
    /// daily totals past the retention setting (D52).
    private func refresh() async {
        clock.refresh()
        let settings = AppSettings()
        do {
            let result = try RollUp.run(in: context, today: clock.today, detailWindowDays: settings.detailWindowDays)
            if !result.daysRolled.isEmpty {
                try context.save()
                Self.log.debug("Rolled up \(result.daysRolled.count) days, \(result.entriesDeleted) entries")
            }
        } catch {
            // Nothing is deleted unless the whole roll-up succeeds; the next open retries.
            Self.log.error("Roll-up failed: \(error.localizedDescription, privacy: .public)")
        }
        await health.sync(into: context, today: clock.today, timeZone: settings.timeZone)
        checkRetention(settings)
    }

    /// Asks before deleting daily totals past the retention setting, at most monthly (D52).
    private func checkRetention(_ settings: AppSettings) {
        guard retentionDue == 0,
              let due = try? Retention.due(today: clock.today, keepDays: settings.summaryRetentionDays, in: context),
              Retention.shouldPrompt(dueCount: due.count, lastPrompt: settings.lastRetentionPrompt, today: clock.today)
        else { return }
        retentionDue = due.count
    }
}

#Preview {
    ContentView()
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
