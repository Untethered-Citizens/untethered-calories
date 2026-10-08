import SwiftUI

/// A tutorial as swipe cards (D58). Swipe or tap Next; Skip leaves early. The key tutorial's
/// last card is the live key step: paste, check with Anthropic, save to the Keychain.
struct TutorialView: View {
    let tutorial: Tutorial
    let context: TutorialContext
    /// Weight unit for the pound rule; nil shows both (onboarding, before a unit is chosen).
    var unit: WeightUnit?
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: TutorialProgress
    @State private var maskedKey: String?

    init(tutorial: Tutorial, context: TutorialContext, unit: WeightUnit? = nil, onFinish: @escaping () -> Void) {
        self.tutorial = tutorial
        self.context = context
        self.unit = unit
        self.onFinish = onFinish
        _progress = State(initialValue: TutorialProgress(tutorial: tutorial, context: context, unit: unit))
    }

    private var cards: [TutorialCard] { tutorial.cards(unit: unit) }

    var body: some View {
        TabView(selection: pageBinding) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                TutorialCardPage(card: card, number: index + 1, count: cards.count,
                                 maskedKey: maskedKey, onKeySaved: reloadKey)
                    .tag(index)
            }
        }
        // The system dots are too faint on the light background; PageDots draws them instead.
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Palette.background)
        .navigationTitle(tutorial.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if progress.canSkip {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { move { progress.skip() } }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear(perform: reloadKey)
    }

    @ViewBuilder private var bottomBar: some View {
        BottomBar {
            PageDots(page: progress.page, count: progress.cardCount)
                .padding(.top, 10)
            if progress.isLast && progress.endsOnKeyStep && context == .onboarding {
                PrimaryButton(title: progress.nextTitle, action: onFinish)
                    .disabled(maskedKey == nil)
                if maskedKey == nil {
                    Button("Skip for now — add it later in Settings", action: onFinish)
                        .font(.barlow(.footnote))
                        .padding(.bottom, 8)
                }
            } else {
                PrimaryButton(title: progress.nextTitle) { move { progress.next() } }
            }
        }
    }

    private var pageBinding: Binding<Int> {
        Binding(get: { progress.page }, set: { progress.setPage($0) })
    }

    /// Runs a paging step, animated unless Reduce Motion is on, and finishes if it says so.
    private func move(_ step: () -> TutorialProgress.Outcome) {
        var outcome = TutorialProgress.Outcome.stay
        withAnimation(reduceMotion ? nil : .default) { outcome = step() }
        if outcome == .finish { onFinish() }
    }

    private func reloadKey() {
        maskedKey = (try? APIKeyStore().load()).flatMap { $0 }.map(APIKeyStore.masked)
    }
}

/// A tutorial replayed from Settings: shown in the user's weight unit, and closing when done.
struct TutorialReplayView: View {
    var tutorial: Tutorial
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TutorialView(tutorial: tutorial, context: .replay, unit: AppSettings().weightUnit) { dismiss() }
    }
}

/// One card: picture, "2 of 7", title, text, steps, link, and for the key step, the key controls.
private struct TutorialCardPage: View {
    var card: TutorialCard
    var number: Int
    var count: Int
    var maskedKey: String?
    var onKeySaved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if card.picture != .addKey {
                    TutorialPictureView(picture: card.picture)
                        // An illustration, not reading text: capped so it keeps its shape (D56).
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .padding(16)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(number) of \(count)")
                        .font(.barlow(.footnote))
                        .foregroundStyle(Palette.muted)
                    Text(card.title)
                        .font(.barlow(.title2, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(card.title). Card \(number) of \(count)")
                .accessibilityAddTraits(.isHeader)

                if !card.body.isEmpty {
                    Text(card.body).foregroundStyle(Palette.ink)
                }
                if !card.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(card.steps.enumerated()), id: \.offset) { index, step in
                            NumberedStep(number: index + 1, text: step)
                        }
                    }
                    .foregroundStyle(Palette.ink)
                }
                if let note = card.note {
                    Text(note).font(.barlow(.footnote)).foregroundStyle(Palette.muted)
                }
                if let link = card.link {
                    Link(destination: link.url) {
                        Label(link.title, systemImage: "arrow.up.right.square")
                    }
                    .font(.barlow(.body, weight: .medium))
                }
                if card.picture == .addKey {
                    KeyControls(maskedKey: maskedKey, onSaved: onKeySaved)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

/// Which card is showing. VoiceOver hears "Card 2 of 7" on the title instead.
private struct PageDots: View {
    var page: Int
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == page ? Palette.green : Palette.rule)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The key step's controls: paste a key, or see the saved one and replace it.
private struct KeyControls: View {
    var maskedKey: String?
    var onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let maskedKey {
                Label {
                    Text("Key saved: \(Text(maskedKey).monospaced())")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
                }
                NavigationLink("Use a different key") {
                    APIKeyEntryView(title: "Replace key", onSaved: onSaved)
                }
            } else {
                NavigationLink {
                    APIKeyEntryView(title: "Add key", onSaved: onSaved)
                } label: {
                    Label("Paste your key", systemImage: "doc.on.clipboard")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Weight tutorial") {
    NavigationStack {
        TutorialView(tutorial: .losingWeight, context: .onboarding) {}
    }
}

#Preview("Key tutorial") {
    NavigationStack {
        TutorialView(tutorial: .aiKey, context: .replay) {}
    }
}
