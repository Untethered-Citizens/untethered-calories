import SwiftUI
import SwiftData

/// First launch: welcome and privacy, the two tutorials (the key tutorial ends on the
/// key step), then targets.
/// Shown once; `onFinish` marks it done and moves to the main screen.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var path: [OnboardingStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep { advance(from: .welcome) }
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .welcome:
                        EmptyView()
                    case .losingWeightTutorial:
                        TutorialView(tutorial: .losingWeight, context: .onboarding) { advance(from: step) }
                    case .keyTutorial:
                        TutorialView(tutorial: .aiKey, context: .onboarding) { advance(from: step) }
                    case .targets:
                        TargetsStep(onFinish: onFinish)
                    }
                }
        }
    }

    private func advance(from step: OnboardingStep) {
        if let next = step.next { path.append(next) }
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
                    Text("Type it or take a photo. Claude works out the calories and macros, and the app keeps the tally. Next, two short tutorials you can skip.")
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

#Preview {
    OnboardingView {}
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
