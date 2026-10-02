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
        .task { await syncWeight() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            clock.refresh()
            Task { await syncWeight() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            clock.refresh()
        }
    }

    /// Weight comes in on launch and every return to the foreground.
    private func syncWeight() async {
        await health.sync(into: context, today: clock.today, timeZone: AppSettings().timeZone)
    }
}

#Preview {
    ContentView()
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
