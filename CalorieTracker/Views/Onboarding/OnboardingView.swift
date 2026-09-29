import SwiftUI
import SwiftData

/// First launch: welcome and privacy, then the API key, then targets.
/// Shown once; `onFinish` marks it done and moves to the main screen.
struct OnboardingView: View {
    var onFinish: () -> Void

    enum Step: Hashable { case key, targets }
    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep { path.append(.key) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .key: KeyStep { path.append(.targets) }
                    case .targets: TargetsStep(onFinish: onFinish)
                    }
                }
        }
    }
}

// MARK: Welcome

private struct WelcomeStep: View {
    var onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Log food by just saying what you ate")
                        .font(.largeTitle.bold())
                    Text("Type it or take a photo. Claude works out the calories and macros, and the app keeps the tally.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 20) {
                    WelcomePoint(icon: "key.fill", title: "Your own Anthropic key",
                          text: "What you type or photograph is sent to Anthropic under your own account, and billed to it. There's no server of ours in between.")
                    WelcomePoint(icon: "iphone", title: "Everything else stays on this iPhone",
                          text: "Your log, totals and targets are stored only here. Photos aren't kept after they're read.")
                    WelcomePoint(icon: "hand.raised.fill", title: "No account, no ads, no tracking",
                          text: "Nothing to sign up for, and nothing about you is collected.")
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar { PrimaryButton(title: "Get started", action: onNext) }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: Key

private struct KeyStep: View {
    var onNext: () -> Void

    @State private var maskedKey: String?

    var body: some View {
        Form {
            Section {
                Text("The app talks to Claude using an API key from Anthropic. You pay Anthropic directly for what you use, usually a small amount per entry.")
            }

            Section {
                NumberedStep(number: 1, text: "Go to console.anthropic.com and sign in, or create an account.")
                NumberedStep(number: 2, text: "Under Billing, add some credit. API use is paid separately from a Claude subscription.")
                NumberedStep(number: 3, text: "Open API Keys, tap Create Key, and copy it.")
                Link(destination: URL(string: "https://console.anthropic.com/")!) {
                    Label("Open the Anthropic Console", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Get a key")
            }

            Section {
                if let maskedKey {
                    LabeledContent("Key saved") {
                        Label(maskedKey, systemImage: "checkmark.circle.fill")
                            .monospaced()
                            .foregroundStyle(.green)
                    }
                    NavigationLink("Use a different key") {
                        APIKeyEntryView(title: "Replace key") { reload() }
                    }
                } else {
                    NavigationLink("Paste your key") {
                        APIKeyEntryView(title: "Add key") { reload() }
                    }
                }
            } header: {
                Text("Add it here")
            } footer: {
                Text("The key is checked with Anthropic (free) and stored only in this iPhone's Keychain.")
            }
        }
        .navigationTitle("Your API key")
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                PrimaryButton(title: "Continue", action: onNext)
                    .disabled(maskedKey == nil)
                if maskedKey == nil {
                    Button("Skip for now — add it later in Settings", action: onNext)
                        .font(.footnote)
                        .padding(.bottom, 8)
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        maskedKey = (try? APIKeyStore().load()).flatMap { $0 }.map(APIKeyStore.masked)
    }
}

// MARK: Targets

private struct TargetsStep: View {
    var onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @State private var targets = MacroTargets.defaults
    @State private var error: String?

    private var today: LocalDate { LocalDate.today(in: AppSettings().timeZone) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Calories", value: targets.calories.formatted())
                LabeledContent("Protein", value: "\(targets.protein) g")
                LabeledContent("Carbs", value: "\(targets.carbs) g")
                LabeledContent("Fat", value: "\(targets.fat) g")
            } header: {
                Text("Your daily targets")
            } footer: {
                Text("You can change these any time in Settings.")
            }

            Section {
                NavigationLink {
                    TargetHelperView { reload() }
                } label: {
                    Label("Work them out for me", systemImage: "wand.and.stars")
                }
                NavigationLink {
                    TargetsEditorView { reload() }
                } label: {
                    Label("I know my numbers", systemImage: "pencil")
                }
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Your targets")
        .safeAreaInset(edge: .bottom) {
            BottomBar { PrimaryButton(title: "Start logging", action: finish) }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        targets = (try? TargetStore.current(on: today, in: context)) ?? .defaults
    }

    /// Records the targets shown, so there's always an explicit version from day one.
    private func finish() {
        do {
            try TargetStore.set(targets, goalNote: (try? TargetStore.goalNote(on: today, in: context)) ?? "",
                                from: today, in: context)
            onFinish()
        } catch {
            self.error = "Couldn't save your targets."
        }
    }
}

// MARK: Pieces

private struct WelcomePoint: View {
    var icon: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}

private struct NumberedStep: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.15), in: Circle())
            Text(text)
        }
    }
}

private struct PrimaryButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).bold().frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

/// The bottom bar holding an onboarding step's main button, with a backing so the list
/// scrolling underneath doesn't show through.
private struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 4) { content }
            .frame(maxWidth: .infinity)
            .background(.bar)
    }
}

#Preview {
    OnboardingView {}
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
