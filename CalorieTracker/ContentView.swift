import SwiftUI
import SwiftData

/// Placeholder home screen for the Phase 1 "hello world" milestone.
/// It proves the data core is wired in: it reads today's entries and shows what's left.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var today = LocalDate.today()
    @State private var remaining = Remaining(targets: .defaults, eaten: .zero)
    @State private var targets = MacroTargets.defaults

    var body: some View {
        VStack(spacing: 8) {
            Text(remaining.isOverCalories ? "\(-remaining.calories)" : "\(remaining.calories)")
                .font(.system(size: 88, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(remaining.isOverCalories ? "calories over target" : "calories left today")
                .foregroundStyle(.secondary)
            Text("Target \(targets.calories) · \(today.iso)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task { refresh() }
    }

    private func refresh() {
        today = LocalDate.today(in: AppSettings().timeZone)
        targets = (try? TargetStore.current(on: today, in: context)) ?? .defaults
        let totals = (try? DayTotalsIndex.load(from: today, through: today, in: context))?[today] ?? .zero
        remaining = Remaining(targets: targets, eaten: totals)
    }
}

#Preview {
    ContentView()
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
