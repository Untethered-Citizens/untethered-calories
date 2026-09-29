import SwiftUI
import SwiftData

/// Edit daily targets. Saving adds a version effective today, so past days
/// keep being judged against the targets that applied then.
struct TargetsEditorView: View {
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var calories = 0
    @State private var protein = 0
    @State private var carbs = 0
    @State private var fat = 0
    @State private var goalNote = ""
    @State private var error: String?
    @State private var loaded = false

    private var today: LocalDate { LocalDate.today(in: AppSettings().timeZone) }

    private var draft: MacroTargets {
        MacroTargets(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    private var macroCalories: Int { Integrity.macroCalories(protein: protein, carbs: carbs, fat: fat) }

    /// Same tolerance as the entry integrity check (D24). A hint only; targets aren't rejected.
    private var macrosDisagree: Bool {
        guard calories > 0 else { return false }
        let gap = abs(macroCalories - calories)
        return gap > Integrity.absoluteSlack && Double(gap) / Double(calories) > Integrity.tolerance
    }

    private var isValid: Bool { calories > 0 && protein >= 0 && carbs >= 0 && fat >= 0 }

    var body: some View {
        Form {
            Section {
                NumberRow(label: "Calories", value: $calories, unit: "cal")
                NumberRow(label: "Protein", value: $protein, unit: "g")
                NumberRow(label: "Carbs", value: $carbs, unit: "g")
                NumberRow(label: "Fat", value: $fat, unit: "g")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your macros add up to \(macroCalories.formatted()) calories.")
                    if macrosDisagree {
                        Text("That's more than 15% away from your calorie target. Check the numbers.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section {
                TextField("For example, lose about 1 lb a week", text: $goalNote)
            } header: {
                Text("Goal (optional)")
            } footer: {
                Text("Changes apply from today. Past days keep the targets they had.")
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Daily targets")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!isValid)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let current = (try? TargetStore.current(on: today, in: context)) ?? .defaults
        calories = current.calories
        protein = current.protein
        carbs = current.carbs
        fat = current.fat
        goalNote = (try? TargetStore.goalNote(on: today, in: context)) ?? ""
    }

    private func save() {
        do {
            try TargetStore.set(draft, goalNote: goalNote.trimmingCharacters(in: .whitespaces),
                                from: today, in: context)
            onSaved()
            dismiss()
        } catch {
            self.error = "Couldn't save your targets."
        }
    }
}

#Preview {
    NavigationStack { TargetsEditorView {} }
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
