import SwiftUI

/// A card for something the model proposed. Nothing is written until the user taps.
/// Path B estimates get one-tap Accept, or Edit first (D14).
struct ProposalCard: View {
    var proposal: LogConversation.Proposal
    var today: LocalDate
    var onAccept: () -> Void
    var onEdit: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            details
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        .opacity(proposal.status == .dismissed ? 0.55 : 1)
    }

    private var header: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.barlow(.subheadline, weight: .semibold))
            Spacer()
            if proposal.status == .pending {
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        switch proposal.kind {
        case .estimate(let entries):
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                EntryLine(draft: entry.draft, showDate: entry.draft.date != today)
            }
            if entries.count > 1 {
                let total = NutritionTotals(entries.map(\.draft))
                Text("Total \(total.calories.formatted()) cal")
                    .font(.barlow(.footnote, weight: .semibold))
            }
        case .targets(let targets, let from, let goalNote):
            Text("\(targets.calories.formatted()) cal · \(targets.protein)p / \(targets.carbs)c / \(targets.fat)f")
                .monospacedDigit()
            Text(from == today ? "From today" : "From \(LogText().dayName(from))")
                .font(.barlow(.footnote)).foregroundStyle(.secondary)
            if !goalNote.isEmpty { Text(goalNote).font(.barlow(.footnote)).foregroundStyle(.secondary) }
        case .usualMeal(let input, let meal, let source, let replaces):
            Text("\(meal.rawValue) · \(input.description)")
            Text("\(input.calories.formatted()) cal · \(input.protein)p / \(input.carbs)c / \(input.fat)f · \(source.rawValue)")
                .font(.barlow(.footnote)).monospacedDigit().foregroundStyle(.secondary)
            if replaces {
                Text("Replaces the one saved with this name.").font(.barlow(.footnote)).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch proposal.status {
        case .pending:
            HStack {
                Button(acceptTitle, action: onAccept)
                    .buttonStyle(.borderedProminent)
                if case .estimate = proposal.kind {
                    Button("Edit", action: onEdit)
                        .buttonStyle(.bordered)
                }
            }
        case .done(let line):
            Label {
                Text(line)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.barlow(.footnote))
        case .dismissed:
            Text("Dismissed. Nothing was saved.")
                .font(.barlow(.footnote)).foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch proposal.kind {
        case .estimate(let entries):
            entries.contains { $0.draft.source == .photoEstimate } ? "Photo estimate" : "Estimate"
        case .targets: "New targets"
        case .usualMeal(let input, _, _, _): "Save \"\(input.name)\""
        }
    }

    private var icon: String {
        switch proposal.kind {
        case .estimate: "sparkles"
        case .targets: "target"
        case .usualMeal: "star"
        }
    }

    private var acceptTitle: String {
        switch proposal.kind {
        case .estimate: "Accept"
        case .targets: "Apply"
        case .usualMeal: "Save"
        }
    }
}

/// One entry: meal, what it was, and the numbers.
struct EntryLine: View {
    var draft: EntryDraft
    var showDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(showDate ? "\(draft.meal.rawValue), \(LogText().dayName(draft.date)) · \(draft.description)"
                          : "\(draft.meal.rawValue) · \(draft.description)")
            HStack(spacing: 4) {
                Text("\(draft.calories.formatted()) cal · \(draft.protein)p / \(draft.carbs)c / \(draft.fat)f")
                if draft.containsAlcohol { Image(systemName: "wineglass").accessibilityLabel("Contains alcohol") }
            }
            .font(.barlow(.footnote))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}

/// Edit entries: an estimate before it's logged, or a saved entry (D44).
/// The source can't change: an estimate stays an estimate.
struct EntryEditView: View {
    var title = "Edit estimate"
    var saveTitle = "Log"
    var original: [EntryDraft]
    var timeZone: TimeZone
    var onSave: ([EntryDraft]) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [EntryDraft] = []
    /// Several items sharing one meal get a single picker that sets them all.
    @State private var oneMeal = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if oneMeal {
                        Section {
                            mealPicker(sharedMealBinding)
                        } footer: {
                            Text("For all \(drafts.count) items.")
                        }
                    }
                    ForEach(drafts.indices, id: \.self) { index in
                        Section {
                            TextField("What it was", text: $drafts[index].description, axis: .vertical)
                            if !oneMeal { mealPicker($drafts[index].meal) }
                            DatePicker("Day", selection: dateBinding(index),
                                       in: ...LocalDate.today(in: timeZone).date(in: timeZone),
                                       displayedComponents: .date)
                                .environment(\.timeZone, timeZone)
                            NumberRow(label: "Calories", value: $drafts[index].calories, unit: "cal")
                            NumberRow(label: "Protein", value: $drafts[index].protein, unit: "g", maxDigits: 4)
                            NumberRow(label: "Carbs", value: $drafts[index].carbs, unit: "g", maxDigits: 4)
                            NumberRow(label: "Fat", value: $drafts[index].fat, unit: "g", maxDigits: 4)
                            Toggle("Contains alcohol", isOn: $drafts[index].containsAlcohol)
                        } header: {
                            Text(drafts.count > 1 ? "Item \(index + 1)" : "Entry")
                        } footer: {
                            footer(for: drafts[index])
                        }
                    }
                    if let error {
                        Text(error).foregroundStyle(.red).font(.barlow(.footnote))
                    }
                }
                .listRowBackground(Palette.panel)
            }
            .themedBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saveTitle, action: save).bold() }
            }
            .onAppear {
                guard drafts.isEmpty else { return }
                drafts = original
                oneMeal = drafts.count > 1 && Set(drafts.map(\.meal)).count == 1
            }
        }
    }

    private func footer(for draft: EntryDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if draft.source == .label {
                Text("From a label.")
            } else {
                Text("Saved as \(draft.source.rawValue.lowercased()). Edited numbers are still an estimate.")
            }
            if Integrity.macroIssue(draft) != nil {
                Text("Protein, carbs and fat add up to \(Integrity.macroCalories(protein: draft.protein, carbs: draft.carbs, fat: draft.fat).formatted()) cal, more than 15% away from the calories. Check the numbers, or turn on alcohol.")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func mealPicker(_ selection: Binding<Meal>) -> some View {
        Picker("Meal", selection: selection) {
            ForEach(Meal.allCases, id: \.self) { Text($0.rawValue) }
        }
    }

    private var sharedMealBinding: Binding<Meal> {
        Binding(get: { drafts.first?.meal ?? .snack },
                set: { meal in drafts.indices.forEach { drafts[$0].meal = meal } })
    }

    private func dateBinding(_ index: Int) -> Binding<Date> {
        Binding(get: { drafts[index].date.date(in: timeZone) },
                set: { drafts[index].date = LocalDate($0, in: timeZone) })
    }

    private func save() {
        do {
            try onSave(drafts)
            dismiss()
        } catch is WriteRejected {
            error = "Some numbers don't add up. Fix the items marked above, then tap \(saveTitle)."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
