import SwiftUI
import SwiftData

/// "Work out my targets": a few questions, a suggested set of targets, and a button to use them.
/// Age, height, weight and sex are used for the sum only and are not stored.
struct TargetHelperView: View {
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let unit = AppSettings().weightUnit

    @State private var sex = TargetCalculator.Sex.female
    @State private var age = 0
    @State private var feet = 0
    @State private var inches = 0
    @State private var centimetres = 0
    @State private var weight = 0
    @State private var activity = TargetCalculator.Activity.light
    @State private var goal = TargetCalculator.Goal.loseFaster
    @State private var error: String?

    private var heightCm: Double {
        unit == .lb ? TargetCalculator.cm(feet: feet, inches: inches) : Double(centimetres)
    }

    private var weightKg: Double { unit.toPounds(Double(weight)) * WeightUnit.kgPerLb }

    /// A result only once every answer is filled in and plausible for an adult.
    private var result: TargetCalculator.Result? {
        guard (18...100).contains(age), (120...230).contains(heightCm), (35...300).contains(weightKg) else { return nil }
        return TargetCalculator.suggest(.init(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
                                              activity: activity, goal: goal))
    }

    var body: some View {
        Form {
            Group {
                Section {
                    Picker("Sex", selection: $sex) {
                        Text("Female").tag(TargetCalculator.Sex.female)
                        Text("Male").tag(TargetCalculator.Sex.male)
                    }
                    .pickerStyle(.segmented)
                    NumberRow(label: "Age", value: $age, unit: "years", maxDigits: 3)
                    if unit == .lb {
                        LabeledContent("Height") {
                            HStack(spacing: 4) {
                                NumberField(placeholder: "–", value: $feet, maxDigits: 1).frame(maxWidth: 40)
                                Text("ft").foregroundStyle(.secondary)
                                NumberField(placeholder: "–", value: $inches, maxDigits: 2).frame(maxWidth: 40)
                                Text("in").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        NumberRow(label: "Height", value: $centimetres, unit: "cm", maxDigits: 3)
                    }
                    NumberRow(label: "Weight", value: $weight, unit: unit.rawValue, maxDigits: 3)
                } header: {
                    Text("About you")
                } footer: {
                    Text("Used only for this sum. None of it is saved. The formula uses sex because resting energy differs on average.")
                }

                Section("How active are you?") {
                    Picker("Activity", selection: $activity) {
                        ForEach(TargetCalculator.Activity.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Your goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(TargetCalculator.Goal.allCases) { Text($0.label(unit)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    if let result {
                        LabeledContent("Calories", value: result.targets.calories.formatted())
                        LabeledContent("Protein", value: "\(result.targets.protein) g")
                        LabeledContent("Carbs", value: "\(result.targets.carbs) g")
                        LabeledContent("Fat", value: "\(result.targets.fat) g")
                        Button("Use these targets", action: save)
                            .frame(maxWidth: .infinity)
                            .bold()
                    } else {
                        Text("Fill in the questions above to see a suggestion.")
                            .foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                } header: {
                    Text("Suggested targets")
                } footer: {
                    if let result {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("About \(result.maintenance.formatted()) calories a day would keep your weight steady.")
                            if result.raisedToMinimum {
                                Text("Your goal would go below \(TargetCalculator.minimumCalories(for: sex).formatted()) calories, so the suggestion stops there. Going lower is best done with a doctor or dietitian.")
                                    .foregroundStyle(.orange)
                            }
                            Text("This is a rough starting point from a standard formula, not medical advice. Watch your weight trend for a few weeks and adjust.")
                        }
                    }
                }
            }
            .listRowBackground(Palette.panel)
        }
        .themedBackground()
        .navigationTitle("Work out my targets")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }

    private func save() {
        guard let result else { return }
        do {
            try TargetStore.set(result.targets, goalNote: goal.label(unit),
                                from: LocalDate.today(in: AppSettings().timeZone), in: context)
            onSaved()
            dismiss()
        } catch {
            self.error = "Couldn't save your targets."
        }
    }
}

#Preview {
    NavigationStack { TargetHelperView {} }
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
