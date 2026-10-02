import SwiftUI
import SwiftData

/// Settings: API key, model, targets, data retention and units.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let settings = AppSettings()
    private let keyStore = APIKeyStore()

    @State private var maskedKey: String?
    @State private var modelID: String?
    @State private var keyError: String?
    @State private var confirmingRemoval = false
    @State private var targets = MacroTargets.defaults

    @State private var detailWindowDays = 14
    @State private var summaryRetention: Int? = 365
    @State private var transcriptDays = 7
    @State private var weightUnit = WeightUnit.lb

    private static let summaryChoices: [Int?] = [90, 180, 365, 730, nil]

    var body: some View {
        NavigationStack {
            Form {
                keySection
                modelSection
                targetsSection
                dataSection
                unitsSection
                #if DEBUG && targetEnvironment(simulator)
                sampleSection
                #endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: detailWindowDays) { _, new in settings.detailWindowDays = new }
            .onChange(of: summaryRetention) { _, new in settings.summaryRetentionDays = new }
            .onChange(of: transcriptDays) { _, new in settings.transcriptRetentionDays = new }
            .onChange(of: weightUnit) { _, new in settings.weightUnit = new }
        }
    }

    // MARK: Sections

    private var keySection: some View {
        Section {
            if let maskedKey {
                LabeledContent("Key") { Text(maskedKey).monospaced() }
                NavigationLink("Replace key") {
                    APIKeyEntryView(title: "Replace key") { reloadKey() }
                }
                Button("Remove key", role: .destructive) { confirmingRemoval = true }
            } else {
                NavigationLink("Add your API key") {
                    APIKeyEntryView(title: "Add key") { reloadKey() }
                }
            }
            if let keyError {
                Text(keyError).foregroundStyle(.red).font(.footnote)
            }
        } header: {
            Text("Anthropic API key")
        } footer: {
            Text("Stored only in this iPhone's Keychain. What you log is sent to Anthropic under your own account and billed to it.")
        }
        .confirmationDialog("Remove your API key?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove key", role: .destructive, action: removeKey)
        } message: {
            Text("Logging by conversation stops working until you add a key again. Your food log stays on this iPhone.")
        }
    }

    private var modelSection: some View {
        Section {
            if maskedKey != nil {
                NavigationLink {
                    ModelPickerView { modelID = settings.modelID }
                } label: {
                    LabeledContent("Model") { Text(modelID ?? "Choose").monospaced() }
                }
            } else {
                LabeledContent("Model", value: modelID ?? "Not chosen yet")
            }
        } header: {
            Text("Model")
        } footer: {
            Text(maskedKey == nil
                 ? "Add your key to choose from Anthropic's current models."
                 : "Sonnet is recommended for logging food.")
        }
    }

    private var targetsSection: some View {
        Section("Daily targets") {
            NavigationLink {
                TargetsEditorView { reloadTargets() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(targets.calories.formatted()) calories")
                    Text("Protein \(targets.protein) g · Carbs \(targets.carbs) g · Fat \(targets.fat) g")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink("Work out my targets") {
                TargetHelperView { reloadTargets() }
            }
        }
    }

    private var dataSection: some View {
        Section {
            Stepper(value: $detailWindowDays, in: 7...90) {
                LabeledContent("Meal detail", value: "\(detailWindowDays) days")
            }
            Picker("Daily totals", selection: $summaryRetention) {
                ForEach(Self.summaryChoices, id: \.self) { days in
                    Text(Self.label(forRetention: days)).tag(days)
                }
            }
            Stepper(value: $transcriptDays, in: 1...30) {
                LabeledContent("Conversations", value: "\(transcriptDays) days")
            }
        } header: {
            Text("Keep on this iPhone")
        } footer: {
            Text("After the meal-detail window, each day's meals are folded into one daily total. Daily totals are kept for the period you choose.")
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    @State private var confirmingSample = false

    private var sampleSection: some View {
        Section {
            Button("Load sample data", role: .destructive) { confirmingSample = true }
                .confirmationDialog("Replace all meals and weights with four weeks of sample data?",
                                    isPresented: $confirmingSample, titleVisibility: .visible) {
                    Button("Replace with sample", role: .destructive) {
                        let settings = AppSettings()
                        try? SampleData.load(into: context, today: LocalDate.today(in: settings.timeZone),
                                             detailWindowDays: settings.detailWindowDays)
                    }
                }
        } header: {
            Text("Simulator only")
        }
    }
    #endif

    private var unitsSection: some View {
        Section {
            Picker("Weight", selection: $weightUnit) {
                ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
            }
            LabeledContent("Time zone", value: settings.timeZone.identifier)
        } header: {
            Text("Units")
        } footer: {
            Text("Days follow this iPhone's time zone.")
        }
    }

    // MARK: Actions

    private func load() {
        reloadKey()
        reloadTargets()
        detailWindowDays = settings.detailWindowDays
        summaryRetention = settings.summaryRetentionDays
        transcriptDays = settings.transcriptRetentionDays
        weightUnit = settings.weightUnit
    }

    private func reloadKey() {
        do {
            maskedKey = try keyStore.load().map(APIKeyStore.masked)
            modelID = settings.modelID
            keyError = nil
        } catch {
            maskedKey = nil
            keyError = "Couldn't read the Keychain."
        }
    }

    private func reloadTargets() {
        targets = (try? TargetStore.current(on: LocalDate.today(in: settings.timeZone), in: context)) ?? .defaults
    }

    private func removeKey() {
        do {
            try keyStore.delete()
            reloadKey()
        } catch {
            keyError = "Couldn't remove the key from the Keychain."
        }
    }

    private static func label(forRetention days: Int?) -> String {
        switch days {
        case nil: "Forever"
        case 365: "1 year"
        case 730: "2 years"
        case let days?: "\(days) days"
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
