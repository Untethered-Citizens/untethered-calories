import SwiftUI
import SwiftData

/// Settings: API key, model, targets, data retention, units, tutorials and About.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthWeight.self) private var health
    @Environment(DayClock.self) private var clock

    private let settings = AppSettings()
    private let keyStore = APIKeyStore()

    @State private var maskedKey: String?
    @State private var modelID: String?
    @State private var keyError: String?
    @State private var confirmingRemoval = false
    @State private var sharing = false
    @State private var askingConsent = false
    @State private var targets = MacroTargets.defaults

    @State private var detailWindowDays = 14
    @State private var summaryRetention: Int? = 365
    @State private var transcriptDays = 7
    @State private var weightUnit = WeightUnit.lb
    @State private var export: ExportFiles?
    @State private var exportError: String?
    @State private var reminderOn = false
    @State private var reminderTime = Date()
    @State private var notificationsDenied = false

    private static let summaryChoices: [Int?] = [90, 180, 365, 730, nil]

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    keySection
                    modelSection
                    targetsSection
                    usualMealsSection
                    reminderSection
                    healthSection
                    dataSection
                    unitsSection
                    tutorialsSection
                    aboutSection
                    #if DEBUG && targetEnvironment(simulator)
                    sampleSection
                    #endif
                }
                .listRowBackground(Palette.panel)
            }
            .themedBackground()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: detailWindowDays) { _, new in settings.detailWindowDays = new }
            .onChange(of: summaryRetention) { _, new in
                settings.summaryRetentionDays = new
                // A new limit should be asked about on the next open, not a month later.
                settings.lastRetentionPrompt = nil
            }
            .sheet(item: $export) { ShareSheet(items: $0.urls) }
            .onChange(of: transcriptDays) { _, new in settings.transcriptRetentionDays = new }
            .onChange(of: weightUnit) { _, new in settings.weightUnit = new }
            .onChange(of: reminderTime) { _, new in
                settings.reminderMinutes = ReminderPlan.minutes(from: new, in: settings.timeZone)
                Task { await ReminderScheduler.reschedule(in: context) }
            }
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
                Toggle("Share with Anthropic", isOn: Binding(get: { sharing }, set: { setSharing($0) }))
                Button("Remove key", role: .destructive) { confirmingRemoval = true }
            } else {
                NavigationLink("Add your AI key") {
                    APIKeyEntryView(title: "Add key") { reloadKey() }
                }
            }
            if let keyError {
                Text(keyError).foregroundStyle(.red).font(.barlow(.footnote))
            }
        } header: {
            Text("Your AI key (Anthropic)")
        } footer: {
            Text(maskedKey == nil || sharing
                 ? "Your key is stored only in this iPhone's Keychain. What you log is sent to Anthropic under your own account and billed to it. Turn off Share with Anthropic to stop sending anything."
                 : "Sharing is off, so nothing is sent to Anthropic and logging by conversation is paused. Everything else still works. Turn it on to see what's sent and allow it.")
        }
        .sheet(isPresented: $askingConsent, onDismiss: reloadKey) {
            AIConsentView { _ in askingConsent = false }
        }
        .confirmationDialog("Remove your AI key?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove key", role: .destructive, action: removeKey)
        } message: {
            Text("Logging by conversation stops working until you add a key again, and a new key asks again before sharing with Anthropic. Your food log stays on this iPhone.")
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
            NavigationLink("Usage and cost") { UsageView() }
        } header: {
            Text("Model")
        } footer: {
            Text(maskedKey == nil
                 ? "Add your AI key to choose from Anthropic's current models."
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
                        .font(.barlow(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink("Work out my targets") {
                TargetHelperView { reloadTargets() }
            }
        }
    }

    private var usualMealsSection: some View {
        Section {
            NavigationLink("Usual meals") { UsualMealsView() }
        } footer: {
            Text("Meals you log by name, with exact numbers.")
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
            Button("Export data (CSV)", systemImage: "square.and.arrow.up") {
                do {
                    export = ExportFiles(urls: try DataExport.files(from: context, unit: settings.weightUnit,
                                                                    today: LocalDate.today(in: settings.timeZone)))
                } catch {
                    exportError = error.localizedDescription
                }
            }
            if let exportError {
                Text("Couldn't create the export: \(exportError)").foregroundStyle(Palette.plum)
            }
        } header: {
            Text("Keep on this iPhone")
        } footer: {
            Text("Meals older than the meal-detail window are folded into one total per day the next time the app opens. You can still see what you ate, but folded meals can no longer be edited one by one. Daily totals are kept for the period you choose. If you set a limit, the app asks before deleting anything, and offers an export first. The Log chat stays on screen for the Conversations period; photos are never kept.")
        }
    }

    private var tutorialsSection: some View {
        Section("Tutorials") {
            ForEach(Tutorial.allCases) { tutorial in
                NavigationLink {
                    TutorialReplayView(tutorial: tutorial)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tutorial.title)
                        Text(tutorial.subtitle).font(.barlow(.footnote)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Link(destination: AppLinks.website) { Label("Website", systemImage: "globe") }
            Link(destination: AppLinks.privacy) { Label("Privacy policy", systemImage: "hand.raised") }
            Link(destination: AppLinks.support) { Label("Help and support", systemImage: "questionmark.circle") }
            LabeledContent("Version", value: AppLinks.versionText())
        } header: {
            Text("About")
        } footer: {
            Text("Links open untetheredcalories.com in Safari.")
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

    private var healthSection: some View {
        Section {
            if !health.isAvailable {
                Text("Apple Health isn't available on this device.")
            } else if health.needsRequest {
                Button("Connect Apple Health") {
                    Task { await health.connect(into: context, today: clock.today, timeZone: settings.timeZone) }
                }
            } else {
                LabeledContent("Weight", value: "Syncs when the app opens")
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("The app reads your weight (the last reading of each day, for the last 90 days). It writes only the weights you add on the Weight tab. If you allow sharing with Anthropic, weights can be sent to answer your questions about earlier days. When iOS asks how much data to share, All Recorded Data brings in the full 90 days. To change access: Settings → Privacy & Security → Health → Untethered.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Remind me to log", isOn: Binding(get: { reminderOn }, set: { setReminder($0) }))
            if reminderOn {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
            }
            if notificationsDenied {
                Button("Allow notifications in iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } header: {
            Text("Daily reminder")
        } footer: {
            if notificationsDenied {
                Text("Notifications are off for this app, so the reminder can't show. Turn them on in iOS Settings → Notifications → Calories.")
            } else {
                Text("A gentle nudge once a day. It's skipped on days you've already logged something.")
            }
        }
    }

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
        reminderOn = settings.reminderEnabled
        reminderTime = ReminderPlan(minutes: settings.reminderMinutes).pickerDate(in: settings.timeZone)
        Task { notificationsDenied = await ReminderScheduler.isDenied() }
    }

    /// Turning the reminder on asks iOS for permission first; if that's refused, it stays off.
    private func setReminder(_ on: Bool) {
        settings.reminderOffered = true
        Task {
            if on {
                let allowed = await ReminderScheduler.requestPermission()
                notificationsDenied = !allowed
                guard allowed else { reminderOn = false; return }
            }
            reminderOn = on
            settings.reminderEnabled = on
            await ReminderScheduler.reschedule(in: context)
        }
    }

    private func reloadKey() {
        do {
            maskedKey = try keyStore.load().map(APIKeyStore.masked)
            modelID = settings.modelID
            sharing = settings.aiConsent == .allowed
            keyError = nil
        } catch {
            maskedKey = nil
            keyError = "Couldn't read the Keychain."
        }
    }

    /// Off withdraws at once. On shows the consent screen again; only Allow turns it on (issue #28).
    private func setSharing(_ on: Bool) {
        if on {
            askingConsent = true
        } else {
            settings.declineAI()
            sharing = false
        }
    }

    private func reloadTargets() {
        targets = (try? TargetStore.current(on: LocalDate.today(in: settings.timeZone), in: context)) ?? .defaults
    }

    private func removeKey() {
        do {
            try keyStore.delete()
            // The next key saved asks again (issue #28).
            settings.resetAIConsent()
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
        .environment(HealthWeight())
        .environment(DayClock())
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
