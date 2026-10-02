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
    /// the window into daily summaries (D51), then bring in weight from Health.
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
    }
}

#Preview {
    ContentView()
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
