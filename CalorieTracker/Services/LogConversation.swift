import Foundation
import Observation
import OSLog
import SwiftData

/// The logging conversation: what's on screen, what's sent to Anthropic, and the cards
/// waiting for a tap.
///
/// The history sent to Anthropic is append-only: nothing already sent is ever edited or
/// removed. Anthropic rejects a conversation whose earlier turns changed (and it would
/// waste the cache), so changing numbers travel in each new user message instead, and a
/// long or stale conversation is replaced by a fresh one rather than trimmed.
@MainActor
@Observable
final class LogConversation {
    struct Item: Identifiable {
        enum Kind {
            /// `photosNotKept` counts photos from before a relaunch: they're never saved (D53).
            case user(String, photos: [Data], photosNotKept: Int = 0)
            case assistant(String)
            /// A Path A write, confirmed in one line.
            case logged(String)
            /// Answered on the phone, with no model call.
            case local(String)
            case proposal(UUID)
            case notice(String)
            /// Marks where a fresh conversation began. Earlier bubbles stay visible but aren't sent.
            case newConversation
        }

        var id = UUID()
        let kind: Kind
        var at = Date()
    }

    struct Proposal: Identifiable, Codable {
        enum Status: Equatable, Codable {
            case pending
            /// Done, with the line shown on the card.
            case done(String)
            case dismissed
        }

        let id: UUID
        var kind: ProposalKind
        var status: Status = .pending
        /// Path A entries logged in the same reply as this estimate (a label item next to
        /// estimated ones). Once the card is accepted, one line covers both (issue #6).
        var loggedAlongside: LoggedAlongside?
    }

    struct LoggedAlongside: Codable {
        /// The separate confirmation lines, removed from the thread once merged.
        var itemIDs: [UUID]
        var drafts: [EntryDraft]
    }

    struct Failure: Equatable {
        var message: String
        /// The unsent message is kept, so Retry resends it.
        var canRetry: Bool
        /// The fix is in Settings (no key, or a key Anthropic rejected).
        var needsKey: Bool = false
        /// Sending to Anthropic isn't allowed (issue #28). The fix is the consent screen.
        var needsConsent: Bool = false
    }

    private(set) var items: [Item] = [] { didSet { persist() } }
    private(set) var proposals: [UUID: Proposal] = [:] { didSet { persist() } }
    private(set) var isSending = false
    private(set) var failure: Failure?
    /// Goes up whenever stored data changes, so screens showing totals can refresh.
    private(set) var revision = 0
    /// Token use of the last reply, for checking the cache works.
    private(set) var lastUsage: MessageResponse.Usage?

    // What's been sent. Append-only within a conversation.
    private(set) var messages: [APIMessage] = []
    /// A user message not yet accepted by Anthropic. Kept for Retry.
    private var outgoing: [JSONValue]?
    /// Results for tool calls that finished without needing the model again (a write or a
    /// card). They lead the user's next message.
    private var deferredResults: [JSONValue] = []
    /// What happened to cards since the model's last turn. Told in the next message.
    private var notes: [String] = []
    private var hasPhoto = false
    private var lastActivity: Date?
    private var conversationDay: LocalDate?

    /// Capabilities per model ID, looked up once per launch.
    var capabilities: [String: ModelCapabilities] = [:]

    private let context: ModelContext
    private let settings: AppSettings
    private let apiKey: () -> String?
    private let transport: HTTPTransport
    private let now: () -> Date
    /// Where the visible chat is kept between launches. Nil keeps it in memory (tests).
    private let store: ChatStore?
    private var restoring = false

    private static let log = Logger(subsystem: "com.frees321.calorietracker", category: "api")

    /// A conversation older than this, or from another day, starts afresh.
    static let idleLimit: TimeInterval = 30 * 60
    /// And so does one that's grown long, which keeps every request small.
    static let messageLimit = 30
    /// Enough for a question or a tool call. Replies are meant to be short.
    static let maxTokens = 4096
    /// Tool rounds allowed for one user message before giving up.
    static let maxRounds = 5

    init(context: ModelContext, settings: AppSettings = AppSettings(),
         apiKey: @escaping () -> String? = { try? APIKeyStore().load() },
         transport: HTTPTransport = URLSessionTransport(),
         now: @escaping () -> Date = Date.init,
         store: ChatStore? = nil) {
        self.context = context
        self.settings = settings
        self.apiKey = apiKey
        self.transport = transport
        self.now = now
        self.store = store
        restore()
    }

    // MARK: Keeping the chat (D53)

    /// Brings back the chat from earlier launches, minus anything past the retention window.
    /// Only the screen comes back: what's sent to Anthropic starts fresh, below a divider.
    private func restore() {
        guard let store, let saved = store.load() else { return }
        let kept = saved.pruned(keepingDays: settings.transcriptRetentionDays, today: today, timeZone: settings.timeZone)
        restoring = true
        items = kept.items.map(\.item)
        proposals = kept.proposals
        restoring = false
        if !items.isEmpty { items.append(Item(kind: .newConversation, at: now())) }
    }

    /// A new chat item, stamped with the app's clock.
    private func entry(_ kind: Item.Kind) -> Item { Item(kind: kind, at: now()) }

    private func persist() {
        guard let store, !restoring else { return }
        store.save(ChatTranscript(items: items.map(ChatTranscript.StoredItem.init), proposals: proposals))
    }

    var today: LocalDate { LocalDate.today(in: settings.timeZone, now: now()) }

    /// Whether the current model takes photos. True until known otherwise.
    var acceptsPhotos: Bool {
        settings.modelID.flatMap { capabilities[$0] }?.imageInput ?? true
    }

    // MARK: Sending

    /// Sends what the user typed and any photos (JPEG). Returns false if nothing was taken,
    /// so the composer can keep the text.
    @discardableResult
    func send(_ rawText: String, photos: [Data] = []) async -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !photos.isEmpty, !isSending else { return false }

        if photos.isEmpty && LocalQuery.isRemainingQuestion(text) {
            items.append(entry(.user(text, photos: [])))
            items.append(entry(.local(localRemainingAnswer())))
            return true
        }
        guard apiKey() != nil else {
            failure = Failure(message: "Add your Anthropic API key in Settings to log by conversation.",
                              canRetry: false, needsKey: true)
            return false
        }
        guard settings.aiConsent == .allowed else {
            failure = Self.failure(for: AnthropicError.noConsent)
            return false
        }

        // A message Anthropic refused outright won't go through by adding to it.
        if let failure, !failure.canRetry, outgoing != nil { startNewConversation() }
        startNewConversationIfStale()
        var content: [JSONValue] = []
        if outgoing == nil {
            content = deferredResults + [ContentBlock.text(logContext().render())]
            deferredResults = []
            notes = []
        }
        content += photos.map(ContentBlock.jpeg)
        if !text.isEmpty { content.append(ContentBlock.text(text)) }
        outgoing = (outgoing ?? []) + content
        if !photos.isEmpty { hasPhoto = true }
        conversationDay = today
        items.append(entry(.user(text, photos: photos)))
        await run()
        return true
    }

    func retry() async {
        guard outgoing != nil, !isSending else { return }
        await run()
    }

    /// True when Claude has nothing to forget: no messages sent yet in this conversation.
    /// The "New chat" button is greyed out then, since tapping it would change nothing.
    var isFresh: Bool { messages.isEmpty && outgoing == nil }

    /// Starts a fresh conversation. Cards already on screen still work.
    func startNewConversation() {
        messages = []
        outgoing = nil
        deferredResults = []
        notes = []
        hasPhoto = false
        lastActivity = nil
        failure = nil
        if let last = items.last, case .newConversation = last.kind { return }
        if !items.isEmpty { items.append(entry(.newConversation)) }
    }

    func clearFailure() { failure = nil }

    private func startNewConversationIfStale() {
        guard !messages.isEmpty || outgoing != nil else { return }
        let idle = lastActivity.map { now().timeIntervalSince($0) > Self.idleLimit } ?? false
        let newDay = conversationDay.map { $0 != today } ?? false
        if (idle || newDay || messages.count >= Self.messageLimit) && outgoing == nil {
            startNewConversation()
        }
    }

    private func run() async {
        guard let key = apiKey() else { return }
        isSending = true
        failure = nil
        defer { isSending = false }
        // Asked again before every request, so withdrawing in Settings stops the next one.
        let client = AnthropicClient(apiKey: key, transport: transport,
                                     mayCreateMessages: { [settings] in settings.aiConsent == .allowed })

        let modelID: String
        do {
            modelID = try await resolveModel(client)
        } catch {
            failure = Self.failure(for: error)
            return
        }
        let caps = await capabilities(of: modelID, client)

        var rounds = 0
        while let content = outgoing {
            rounds += 1
            guard rounds <= Self.maxRounds else {
                // Leave the conversation valid: answer the open tool calls, then stop.
                deferredResults = content.filter { $0["type"]?.stringValue == "tool_result" }
                outgoing = nil
                items.append(entry(.notice("That took too many steps. Try saying it another way.")))
                return
            }
            let request = MessagesRequest(model: modelID, maxTokens: Self.maxTokens, system: SystemPrompt.text,
                                          tools: LogTool.definitions(strict: caps.strictTools),
                                          messages: messages + [.user(content)],
                                          effort: caps.lowEffort ? "low" : nil)
            let response: MessageResponse
            let started = Date()
            do {
                response = try await client.createMessage(request)
                #if DEBUG
                // Token counts only. The key and the food text are never logged.
                let u = response.usage
                Self.log.debug("reply \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s stop=\(response.stopReason ?? "-", privacy: .public) in=\(u?.inputTokens ?? 0) out=\(u?.outputTokens ?? 0) cacheRead=\(u?.cacheReadInputTokens ?? 0) cacheWrite=\(u?.cacheCreationInputTokens ?? 0)")
                #endif
            } catch {
                failure = Self.failure(for: error)
                return
            }
            messages.append(.user(content))
            messages.append(APIMessage(role: "assistant", content: response.content))
            outgoing = nil
            lastActivity = now()
            lastUsage = response.usage
            if let usage = response.usage {
                // Counts only, for the cost estimate in Settings (D55). Never the text.
                try? UsageLedger.record(usage, model: modelID, newMessage: rounds == 1, on: today, in: context)
            }
            handle(response)
        }
    }

    private func handle(_ response: MessageResponse) {
        let calls = response.toolCalls
        // A direct log gets the app's own one-line confirmation, so any words alongside it are noise.
        let logsDirectly = calls.contains { $0.name == LogTool.logEntries.rawValue }
        if !response.text.isEmpty && !logsDirectly { items.append(entry(.assistant(response.text))) }

        guard response.stopReason == "tool_use" else {
            // Every tool call needs an answer in the next message, even a cut-off one.
            deferredResults = calls.map {
                ContentBlock.toolResult(id: $0.id, text: "The reply was cut off before this ran. Call it again if still needed.", isError: true)
            }
            switch response.stopReason {
            case "max_tokens":
                items.append(entry(.notice("The reply was cut off. Try asking for less at once.")))
            case "refusal":
                items.append(entry(.notice("Claude declined to answer that. Try rewording it.")))
            default:
                break
            }
            return
        }

        let runner = ToolRunner(context: context, today: today, conversationHasPhoto: hasPhoto)
        var results: [JSONValue] = []
        var allTerminal = true
        var logged = LoggedAlongside(itemIDs: [], drafts: [])
        var estimateCard: UUID?
        for call in calls {
            let outcome = runner.run(call)
            results.append(ContentBlock.toolResult(id: call.id, text: outcome.text, isError: outcome.isError))
            allTerminal = allTerminal && outcome.isTerminal
            switch outcome.effect {
            case .none: break
            case .logged(let line, let drafts):
                let item = entry(.logged(line))
                items.append(item)
                logged.itemIDs.append(item.id)
                logged.drafts += drafts
                revision += 1
            case .proposal(let kind):
                let id = UUID()
                proposals[id] = Proposal(id: id, kind: kind)
                items.append(entry(.proposal(id)))
                if case .estimate = kind, estimateCard == nil { estimateCard = id }
            }
        }
        // One meal, half from a label and half estimated, still reads as one meal once accepted.
        if let estimateCard, !logged.itemIDs.isEmpty {
            proposals[estimateCard]?.loggedAlongside = logged
        }
        if allTerminal {
            deferredResults = results
        } else {
            outgoing = results
        }
    }

    // MARK: Cards

    /// Accepts a card as proposed.
    func accept(_ id: UUID) {
        guard let proposal = proposals[id], proposal.status == .pending else { return }
        switch proposal.kind {
        case .estimate(let entries):
            commitEstimate(id, entries: entries, edited: false)
        case .targets(let targets, let from, let goalNote):
            do {
                try TargetStore.set(targets, goalNote: goalNote, from: from, in: context)
                finish(id, line: from == today ? "Targets updated from today." : "Targets updated from \(LogText().dayName(from)).",
                       note: "The user applied the proposed targets (\(targets.calories) kcal, \(targets.protein)p/\(targets.carbs)c/\(targets.fat)f from \(from.iso)).")
            } catch {
                failure = Failure(message: "Couldn't save the targets: \(error.localizedDescription)", canRetry: false)
            }
        case .usualMeal(let input, let meal, let source, _):
            do {
                let runner = ToolRunner(context: context, today: today, conversationHasPhoto: hasPhoto)
                if let existing = runner.findUsualMeal(input.name) { context.delete(existing) }
                context.insert(UsualMeal(name: input.name, triggerPhrases: input.triggerPhrases, meal: meal,
                                         description: input.description, calories: input.calories,
                                         protein: input.protein, carbs: input.carbs, fat: input.fat,
                                         source: source, containsAlcohol: input.containsAlcohol))
                try context.save()
                finish(id, line: "Saved as \"\(input.name)\".",
                       note: "The user saved the usual meal \"\(input.name)\".")
            } catch {
                failure = Failure(message: "Couldn't save the meal: \(error.localizedDescription)", canRetry: false)
            }
        }
    }

    /// Logs an estimate after the user edited it. The source stays an estimate.
    /// Throws `WriteRejected` if the edited numbers fail the integrity check.
    func acceptEdited(_ id: UUID, drafts: [EntryDraft]) throws {
        guard let proposal = proposals[id], proposal.status == .pending,
              case .estimate(let original) = proposal.kind, original.count == drafts.count else { return }
        let entries = zip(original, drafts).map { PendingEntry(draft: $1, origin: $0.origin) }
        try validate(entries)
        commitEstimate(id, entries: entries, edited: true)
    }

    func dismiss(_ id: UUID) {
        guard var proposal = proposals[id], proposal.status == .pending else { return }
        proposal.status = .dismissed
        proposals[id] = proposal
        notes.append("The user dismissed your \(Self.describe(proposal.kind)). Nothing was saved.")
    }

    private func validate(_ entries: [PendingEntry]) throws {
        var problems: [Int: [IntegrityIssue]] = [:]
        for (index, entry) in entries.enumerated() {
            let found = Integrity.issues(for: entry.draft, origin: entry.origin, confirmedByUser: true)
            if !found.isEmpty { problems[index] = found }
        }
        if !problems.isEmpty { throw WriteRejected(issues: problems) }
    }

    private func commitEstimate(_ id: UUID, entries: [PendingEntry], edited: Bool) {
        do {
            try EntryWriter.commit(entries, confirmedByUser: true, in: context)
            try context.save()
            let runner = ToolRunner(context: context, today: today, conversationHasPhoto: hasPhoto)
            let alongside = proposals[id]?.loggedAlongside
            let line = try runner.confirmation(for: (alongside?.drafts ?? []) + entries.map(\.draft))
            if let alongside {
                // The combined line replaces the earlier one, so the meal isn't confirmed twice.
                let merged = Set(alongside.itemIDs)
                items.removeAll { merged.contains($0.id) }
            }
            let what = entries.map { "\($0.draft.description) (\($0.draft.calories) kcal, \($0.draft.protein)p/\($0.draft.carbs)c/\($0.draft.fat)f)" }
                .joined(separator: "; ")
            finish(id, line: line, note: edited
                   ? "The user edited your estimate and logged: \(what)."
                   : "The user accepted your estimate and it was logged: \(what).")
            revision += 1
        } catch {
            failure = Failure(message: "Couldn't log that: \(error.localizedDescription)", canRetry: false)
        }
    }

    private func finish(_ id: UUID, line: String, note: String) {
        proposals[id]?.status = .done(line)
        // Only worth telling a conversation that's still going.
        if !messages.isEmpty { notes.append(note) }
    }

    private static func describe(_ kind: ProposalKind) -> String {
        switch kind {
        case .estimate(let entries): "estimate for " + entries.map(\.draft.description).joined(separator: "; ")
        case .targets: "proposed targets"
        case .usualMeal(let input, _, _, _): "usual meal \"\(input.name)\""
        }
    }

    // MARK: Context

    func logContext() -> LogContext {
        let day = today
        let targets = (try? TargetStore.current(on: day, in: context)) ?? .defaults
        let eaten = (try? DayTotalsIndex.load(from: day, through: day, in: context))?[day] ?? .zero
        let usual = ((try? context.fetch(FetchDescriptor<UsualMeal>(sortBy: [SortDescriptor(\.name)]))) ?? []).map {
            LogContext.UsualMealLine(name: $0.name, triggerPhrases: $0.triggerPhrases, meal: $0.meal,
                                     description: $0.foodDescription, calories: $0.calories, protein: $0.protein,
                                     carbs: $0.carbs, fat: $0.fat, source: $0.source, containsAlcohol: $0.containsAlcohol)
        }
        return LogContext(now: now(), timeZone: settings.timeZone, targets: targets, eaten: eaten,
                          usualMeals: usual, notes: notes)
    }

    private func localRemainingAnswer() -> String {
        let context = logContext()
        return LogText().remainingAnswer(eaten: context.eaten, target: context.targets)
    }

    // MARK: Model

    private func resolveModel(_ client: AnthropicClient) async throws -> String {
        if let id = settings.modelID { return id }
        // No model chosen yet (the key was added without the picker): use the recommendation.
        let models = try await client.listModels()
        guard let id = ModelRecommendation.resolve(current: nil, in: models) else {
            throw AnthropicError.other(status: 0, message: "This key can't use any models.")
        }
        settings.modelID = id
        return id
    }

    private func capabilities(of modelID: String, _ client: AnthropicClient) async -> ModelCapabilities {
        if let known = capabilities[modelID] { return known }
        // If the lookup fails, send the plainest request, which every model accepts.
        guard let found = try? await client.capabilities(of: modelID) else { return .unknown }
        capabilities[modelID] = found
        return found
    }

    static func failure(for error: Error) -> Failure {
        guard let error = error as? AnthropicError else {
            return Failure(message: "Something went wrong: \(error.localizedDescription)", canRetry: true)
        }
        switch error {
        case .invalidKey:
            return Failure(message: "Anthropic didn't accept your API key. Replace it in Settings.", canRetry: false, needsKey: true)
        case .offline:
            return Failure(message: "You're offline. Your message is kept; tap Retry when you're connected.", canRetry: true)
        case .rateLimited(let seconds):
            let wait = seconds.map { "in \($0) seconds" } ?? "in a minute"
            return Failure(message: "Anthropic is limiting requests right now. Try again \(wait).", canRetry: true)
        case .serverBusy:
            return Failure(message: "Anthropic is busy right now. Tap Retry in a moment.", canRetry: true)
        case .noConsent:
            return Failure(message: "Sharing with Anthropic is off, so nothing was sent.",
                           canRetry: false, needsConsent: true)
        case .billing, .permissionDenied:
            return Failure(message: error.userMessage, canRetry: true)
        case .other(let status, let message):
            if status == 400 || status == 413 {
                return Failure(message: "Anthropic couldn't take that message (\(message)). Start a new conversation and try again.", canRetry: false)
            }
            return Failure(message: error.userMessage, canRetry: true)
        }
    }
}
