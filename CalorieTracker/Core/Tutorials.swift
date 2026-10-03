import Foundation

/// The two swipe-card tutorials (D58): offered during onboarding, replayable from Settings.
/// Content only; the cards are drawn by `TutorialView`.
enum Tutorial: String, CaseIterable, Identifiable, Sendable {
    case losingWeight, aiKey

    var id: String { rawValue }

    /// The maker's name for card 7 of the key tutorial. Nil until it's chosen (Phase 6),
    /// which drops the "future apps from …" clause rather than showing a placeholder.
    static let makerName: String? = nil

    static let consoleURL = URL(string: "https://platform.claude.com/")!
    static let apiKeysURL = URL(string: "https://platform.claude.com/settings/keys")!

    var title: String {
        switch self {
        case .losingWeight: "How the app helps you lose weight"
        case .aiKey: "Your AI key"
        }
    }

    /// Fits the navigation bar.
    var shortTitle: String {
        switch self {
        case .losingWeight: "Losing weight"
        case .aiKey: "Your AI key"
        }
    }

    var subtitle: String {
        switch self {
        case .losingWeight: "Calorie deficits, macros, and what the app shows you"
        case .aiKey: "What an API key is, and how to get one"
        }
    }

    /// The cards in order. `unit` is the weight unit for the pound rule; nil (during
    /// onboarding, before a unit is chosen) shows both.
    func cards(unit: WeightUnit? = nil) -> [TutorialCard] {
        switch self {
        case .losingWeight: Self.weightCards(unit: unit)
        case .aiKey: Self.keyCards
        }
    }

    private static func weightCards(unit: WeightUnit?) -> [TutorialCard] {
        let rule = switch unit {
        case nil: "A rough rule: about 3,500 calories make a pound (7,700 a kilogram). Eating 500 fewer a day is about a pound a week."
        case .lb: "A rough rule: about 3,500 calories make a pound. Eating 500 fewer a day is about a pound a week."
        case .kg: "A rough rule: about 7,700 calories make a kilogram. Eating 500 fewer a day is about half a kilogram a week."
        }
        return [
            TutorialCard(title: "Eat a little less than you burn",
                         body: "Your body burns energy all day. Eat a bit less than that, and it makes up the difference from stored fat. That gap is called a calorie deficit, and it's what moves your weight.",
                         picture: .deficit),
            TutorialCard(title: "Small and steady wins",
                         body: rule + " It's an estimate, and progress slows as you get lighter, but it's a sound place to start.",
                         picture: .weekOfDeficit(unit: unit ?? .lb)),
            TutorialCard(title: "Calories count. So does protein.",
                         body: "Protein, carbs and fat are your macros. Enough protein helps you keep muscle and stay full while you eat less. Carbs and fat make up the rest. The app tracks all three next to calories.",
                         picture: .macros),
            TutorialCard(title: "A budget, then a journal",
                         body: "You set a daily calorie and macro target, or let the app work one out from your size, age and activity. Then just say what you ate. \"Calories left today\" counts down as you go.",
                         picture: .logExample),
            TutorialCard(title: "Labels are exact. Guesses say so.",
                         body: "Numbers from a label are logged as Label. When Claude estimates from a description or a food photo, it's marked as an estimate and you confirm it first. The Week tab shows how much of your week was estimated.",
                         picture: .sources),
            TutorialCard(title: "Proof takes a few weeks",
                         body: "Daily weight jumps around with water and salt, so the Weight tab shows a 7-day average. After about three weeks of logging and weighing in, the Trend tab compares what you ate with how your weight moved.",
                         picture: .weightTrend),
            TutorialCard(title: "A starting point, not medical advice",
                         body: "The app won't suggest less than 1,200 calories a day for women or 1,500 for men. If you're pregnant, have a medical condition, or have a history of disordered eating, talk to a doctor or dietitian first.",
                         picture: .safety),
        ]
    }

    private static var keyCards: [TutorialCard] {
        let manyApps = makerName.map {
            "The same key works in other apps that let you bring your own key, including future apps from \($0)."
        } ?? "The same key works in other apps that let you bring your own key."
        return [
            TutorialCard(title: "A key is a password for apps",
                         body: "An API key is a long code that lets an app use Claude under your own Anthropic account. Think of it as a password you give to one app, which you can cancel at any time.",
                         picture: .keyConcept),
            TutorialCard(title: "No middleman",
                         body: "There's no account to make with us, no subscription and no server of ours. What you type or photograph goes straight from your iPhone to Anthropic. Your log stays on this iPhone.",
                         picture: .direct),
            TutorialCard(title: "Pay only for what you use",
                         body: "Anthropic bills your account for each message, usually less than a cent to a couple of cents per entry (a photo costs a little more). You can see what you've spent in Settings → Usage and cost.",
                         picture: .cost),
            TutorialCard(title: "Create an Anthropic account",
                         steps: ["Open platform.claude.com and sign up.",
                                 "Go to Billing and add a little credit. $5 lasts most people months.",
                                 "Set a monthly spend limit so you're never surprised."],
                         note: "API use is billed separately from a Claude.ai subscription.",
                         link: TutorialLink(title: "Open the Anthropic Console", url: consoleURL),
                         picture: .billing),
            TutorialCard(title: "Create and copy your key",
                         steps: ["Go to Settings → API keys and tap Create key.",
                                 "Name it after this app, and choose no expiry (or a long one).",
                                 "Copy the key. It starts with \"sk-ant-\" and is shown only once."],
                         link: TutorialLink(title: "Open API keys", url: apiKeysURL),
                         picture: .createKey),
            TutorialCard(title: "Treat it like a password",
                         body: "The app keeps your key only in this iPhone's Keychain and never shows it in full. Don't share it or post it. If you think it leaked, delete it in the Console and paste a new one here.",
                         picture: .keySafety),
            TutorialCard(title: "Works beyond this app",
                         body: manyApps + " You can also make a separate key for each app, so you can see and cancel them one by one.",
                         picture: .oneKeyManyApps),
            TutorialCard(title: "Add your key",
                         body: "Paste the key you copied. The app checks it with Anthropic (free) and saves it to the Keychain.",
                         picture: .addKey),
        ]
    }
}

struct TutorialCard: Identifiable, Equatable, Sendable {
    var title: String
    var body: String = ""
    /// Numbered steps, shown after the body.
    var steps: [String] = []
    /// A short line after the steps.
    var note: String?
    var link: TutorialLink?
    var picture: TutorialPicture

    var id: String { title }

    /// Everything the card says, as one string (for VoiceOver and the length check).
    var fullText: String {
        ([body] + steps.enumerated().map { "\($0.offset + 1). \($0.element)" } + [note ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct TutorialLink: Equatable, Sendable {
    var title: String
    var url: URL
}

/// The illustration drawn at the top of a card. `addKey` is the live key step, not a picture.
enum TutorialPicture: Equatable, Sendable {
    case deficit, weekOfDeficit(unit: WeightUnit), macros, logExample, sources, weightTrend, safety
    case keyConcept, direct, cost, billing, createKey, keySafety, oneKeyManyApps, addKey
}

/// Where a tutorial is being shown. Onboarding moves on to the next step when it ends;
/// a replay from Settings just closes.
enum TutorialContext: Sendable {
    case onboarding, replay
}

/// Paging through a tutorial's cards. Pure state, so the rules are testable.
struct TutorialProgress: Equatable {
    let tutorial: Tutorial
    let context: TutorialContext
    let cardCount: Int
    private(set) var page = 0

    init(tutorial: Tutorial, context: TutorialContext, unit: WeightUnit? = nil) {
        self.tutorial = tutorial
        self.context = context
        self.cardCount = tutorial.cards(unit: unit).count
    }

    var isLast: Bool { page == cardCount - 1 }

    /// The key tutorial ends on the live key step, which has its own buttons.
    var endsOnKeyStep: Bool { tutorial == .aiKey }

    /// What the main button says on this card.
    var nextTitle: String {
        guard isLast else { return "Next" }
        return switch (tutorial, context) {
        case (.losingWeight, _): "Got it"
        case (.aiKey, .onboarding): "Continue"
        case (.aiKey, .replay): "Done"
        }
    }

    /// Skip is offered on every card but the last. In onboarding the key tutorial's Skip
    /// jumps to the key step instead of leaving, so the key is always offered (D34).
    var canSkip: Bool { !isLast }

    enum Outcome: Equatable { case stay, finish }

    mutating func setPage(_ newPage: Int) {
        page = min(max(newPage, 0), cardCount - 1)
    }

    mutating func next() -> Outcome {
        if isLast { return .finish }
        page += 1
        return .stay
    }

    mutating func skip() -> Outcome {
        if tutorial == .aiKey && context == .onboarding {
            page = cardCount - 1
            return .stay
        }
        return .finish
    }
}

/// The first-launch screens in order (D34, D58): the tutorials come before the key and
/// targets, and the key step is the key tutorial's last card.
enum OnboardingStep: Hashable, CaseIterable, Sendable {
    case welcome, losingWeightTutorial, keyTutorial, targets

    var next: OnboardingStep? {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return index + 1 < all.count ? all[index + 1] : nil
    }
}
