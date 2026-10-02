import SwiftUI
import SwiftData

/// The home screen: five tabs, Log first (D45). Reopens on the last tab used.
struct ContentView: View {
    enum TabID: String {
        case log, today, week, weight, trend
    }

    @AppStorage("selectedTab") private var selected = TabID.log
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = DayClock()

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
        .onChange(of: scenePhase) { _, phase in if phase == .active { clock.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            clock.refresh()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
