import SwiftUI
import SwiftData

/// Tab 2: how the day is going. Calories left, the budget strip by source, macros, and
/// the meals, which can be swiped to edit or delete.
struct TodayView: View {
    @Environment(DayClock.self) private var clock
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            TodayContent(today: clock.today)
                .id(clock.today)
                .navigationTitle("Today")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    }
                }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

private struct TodayContent: View {
    let today: LocalDate

    @Query private var entries: [MealEntry]
    @Query private var targetRows: [Targets]
    @State private var editing: MealEntry?
    @State private var deleting: MealEntry?

    init(today: LocalDate) {
        self.today = today
        let key = today.iso
        _entries = Query(filter: #Predicate<MealEntry> { $0.dayKey == key })
    }

    private var sorted: [MealEntry] { entries.sorted(by: MealEntry.detailOrder) }
    private var targets: MacroTargets { TargetHistory.effective(on: today, in: targetRows.map(\.period)) }

    var body: some View {
        let eaten = NutritionTotals(entries)
        let remaining = Remaining(targets: targets, eaten: eaten)
        List {
            Group {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LogText().dayName(today, template: "EEEE MMM d"))
                        .font(.barlow(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    HeroNumber(value: abs(remaining.calories).formatted(),
                               unit: remaining.isOverCalories ? "calories\nover target" : "calories\nleft today",
                               over: remaining.isOverCalories)
                    eatenLine(eaten)
                        .padding(.bottom, 8)
                    BudgetStrip(entries: sorted.map(\.draft), target: targets.calories)
                    SourceLegend()
                }
                SectionHeading(title: "Macros")
                MacroBars(protein: Double(eaten.protein), carbs: Double(eaten.carbs),
                          fat: Double(eaten.fat), targets: targets)
                SectionHeading(title: "Meals")
            }
            .dashboardRow()

            MealsSection(entries: sorted, empty: "Nothing logged yet. Tell the Log tab what you ate.",
                         editing: $editing, deleting: $deleting)
        }
        .listStyle(.plain)
        .entryActions(editing: $editing, deleting: $deleting)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    private func eatenLine(_ eaten: NutritionTotals) -> some View {
        Group {
            if entries.isEmpty {
                Text("Nothing logged yet today.")
            } else {
                Text("\(Text(eaten.calories.formatted()).fontWeight(.semibold).foregroundStyle(Palette.ink)) eaten of \(Text(targets.calories.formatted()).fontWeight(.semibold).foregroundStyle(Palette.ink)) across \(entries.count) \(entries.count == 1 ? "entry" : "entries")")
            }
        }
        .foregroundStyle(Palette.muted)
    }
}

/// A day's entries, each swipeable to edit or delete (D44). The sheets live on the list
/// (see `entryActions`), not on the rows.
struct MealsSection: View {
    var entries: [MealEntry]
    var empty: String
    @Binding var editing: MealEntry?
    @Binding var deleting: MealEntry?

    var body: some View {
        if entries.isEmpty {
            Text(empty).foregroundStyle(Palette.muted).dashboardRow()
        }
        ForEach(entries) { entry in
            MealRow(draft: entry.draft)
                .dashboardRow(separator: true)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                        .tint(.red)
                    Button("Edit", systemImage: "pencil") { editing = entry }
                        .tint(Palette.green)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editing = entry }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                }
        }
    }
}

/// The edit sheet and delete confirmation for `MealsSection`. Edits and deletes go
/// through the write boundary.
struct EntryActions: ViewModifier {
    @Binding var editing: MealEntry?
    @Binding var deleting: MealEntry?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .sheet(item: $editing) { entry in
                EntryEditView(title: "Edit entry", saveTitle: "Save", original: [entry.draft],
                              timeZone: AppSettings().timeZone) { drafts in
                    try EntryWriter.update(entry, to: drafts[0], in: context)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: deletingBinding, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let deleting { try? EntryWriter.delete(deleting, in: context) }
                    deleting = nil
                }
            }
    }

    private var deleteTitle: String {
        guard let deleting else { return "" }
        return "Delete \(deleting.meal.rawValue.lowercased()): \(deleting.foodDescription), \(deleting.calories.formatted()) cal?"
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

extension View {
    func entryActions(editing: Binding<MealEntry?>, deleting: Binding<MealEntry?>) -> some View {
        modifier(EntryActions(editing: editing, deleting: deleting))
    }
}
