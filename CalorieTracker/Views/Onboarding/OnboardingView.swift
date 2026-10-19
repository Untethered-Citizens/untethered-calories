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
            VStack(alignment: .leading, spacing: 24) {
                BrandLockup()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Log food by just saying what you ate")
                        .font(.custom(BrandFont.condensed(.semibold), size: 42, relativeTo: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                    Text("Type it or take a photo. Claude works out the calories and macros, and the app keeps the tally. Next, two short tutorials you can skip.")
                        .foregroundStyle(Palette.muted)
                }

                VStack(spacing: 0) {
                    WelcomePoint(icon: "key", title: "Bring your own AI",
                          text: "You add your own AI key from Anthropic. Once you allow it, what you log is sent to Anthropic under your account, and billed to it. There's no server of ours in between.")
                    Divider().overlay(Palette.rule).padding(.leading, 70)
                    WelcomePoint(icon: "iphone", title: "Stored only on this iPhone",
                          text: "Your log, totals, targets and weights are stored only here. Copies go to Anthropic only as the app explains before you allow it. Photos aren't kept after they're read.")
                    Divider().overlay(Palette.rule).padding(.leading, 70)
                    WelcomePoint(icon: "hand.raised", title: "No account, no ads, no tracking",
                          text: "Nothing to sign up for, and we collect nothing.")
                }
                .background(Palette.panel, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.rule))

                Link("Read our privacy policy", destination: AppLinks.privacy)
                    .font(.barlow(.subheadline))
                    .foregroundStyle(Palette.green)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom) {
            BottomBar { PrimaryButton(title: "Get started", action: onNext) }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The mark beside the app's name, as on the welcome screen.
private struct BrandLockup: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("BrandMark")
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            Text("Untethered Calories")
                .font(.condensed(22, relativeTo: .title3))
        }
        .accessibilityElement(children: .combine)
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
            Group {
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
            .listRowBackground(Palette.panel)
        }
        .themedBackground()
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
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Palette.green)
                .frame(width: 40, height: 40)
                .background(Palette.track, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.barlow(.headline))
                Text(text).font(.barlow(.subheadline)).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView {}
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
