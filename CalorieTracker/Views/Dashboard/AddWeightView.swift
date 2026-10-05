import SwiftUI
import SwiftData

/// Type in a weigh-in. It's saved to Apple Health, and arrives here through the normal sync,
/// so a reading from the app and one from a scale are treated exactly alike.
struct AddWeightView: View {
    var latestPounds: Double?

    @Environment(HealthWeight.self) private var health
    @Environment(DayClock.self) private var clock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var taken = Date()
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private let settings = AppSettings()
    private var unit: WeightUnit { settings.weightUnit }
    private var value: Double? { WeightEntry.value(from: text, unit: unit) }

    /// Back-dating is fine, within the window the sync reads.
    private var allowed: ClosedRange<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = settings.timeZone
        let start = WeightImport.windowStart(today: clock.today).date(in: settings.timeZone)
        return calendar.startOfDay(for: start)...Date()
    }

    private var placeholder: String {
        latestPounds.map { unit.fromPounds($0).formatted(.number.precision(.fractionLength(1))) } ?? "0.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        LabeledContent("Weight") {
                            HStack(spacing: 4) {
                                TextField(placeholder, text: $text)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .focused($focused)
                                Text(unit.rawValue).foregroundStyle(.secondary)
                            }
                        }
                        DatePicker("When", selection: $taken, in: allowed)
                    } footer: {
                        Text("Saved to Apple Health, where readings from a smart scale go too. If you weigh in more than once a day, the last one counts.")
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(Palette.plum) }
                    }
                }
                .listRowBackground(Palette.panel)
            }
            .themedBackground()
            .navigationTitle("Add weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save", action: save).disabled(value == nil)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        guard let value else { return }
        saving = true
        error = nil
        Task {
            do {
                try await health.save(value, unit: unit, at: taken, into: context,
                                      today: clock.today, timeZone: settings.timeZone)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
