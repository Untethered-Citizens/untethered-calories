import Foundation
import OSLog

/// The visible logging chat, as kept between launches (D53). Only what's on screen: never
/// photos, and never the conversation sent to Anthropic.
struct ChatTranscript: Codable {
    struct StoredItem: Codable {
        enum Kind: String, Codable {
            case user, assistant, logged, local, proposal, notice, newConversation
        }

        var id: UUID
        var at: Date
        var kind: Kind
        var text: String?
        var photoCount: Int?
        var proposalID: UUID?

        init(_ item: LogConversation.Item) {
            id = item.id
            at = item.at
            switch item.kind {
            case .user(let text, let photos, let notKept):
                kind = .user
                self.text = text
                let count = photos.count + notKept
                photoCount = count > 0 ? count : nil
            case .assistant(let text): kind = .assistant; self.text = text
            case .logged(let text): kind = .logged; self.text = text
            case .local(let text): kind = .local; self.text = text
            case .notice(let text): kind = .notice; self.text = text
            case .proposal(let id): kind = .proposal; proposalID = id
            case .newConversation: kind = .newConversation
            }
        }

        var item: LogConversation.Item {
            let restored: LogConversation.Item.Kind = switch kind {
            case .user: .user(text ?? "", photos: [], photosNotKept: photoCount ?? 0)
            case .assistant: .assistant(text ?? "")
            case .logged: .logged(text ?? "")
            case .local: .local(text ?? "")
            case .notice: .notice(text ?? "")
            case .proposal: proposalID.map { .proposal($0) } ?? .notice("")
            case .newConversation: .newConversation
            }
            return LogConversation.Item(id: id, kind: restored, at: at)
        }
    }

    var items: [StoredItem]
    var proposals: [UUID: LogConversation.Proposal]

    /// Keeps the last `keepingDays` calendar days, today included, and only the cards still
    /// shown. A divider left at the top, or two in a row, is dropped.
    func pruned(keepingDays: Int, today: LocalDate, timeZone: TimeZone) -> ChatTranscript {
        let first = today.adding(days: -(max(1, keepingDays) - 1))
        var kept: [StoredItem] = []
        for item in items where LocalDate(item.at, in: timeZone) >= first {
            if item.kind == .newConversation && (kept.isEmpty || kept.last?.kind == .newConversation) { continue }
            kept.append(item)
        }
        if kept.last?.kind == .newConversation { kept.removeLast() }
        let shown = Set(kept.compactMap(\.proposalID))
        return ChatTranscript(items: kept, proposals: proposals.filter { shown.contains($0.key) })
    }
}

/// Reads and writes the transcript as one small JSON file in Application Support.
/// It's protected with the phone's passcode like the rest of the app's data.
final class ChatStore {
    let url: URL
    private static let log = Logger(subsystem: "com.untetheredcitizens.calories", category: "chat")

    init(url: URL) {
        self.url = url
    }

    static let standard: ChatStore = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ChatStore(url: folder.appendingPathComponent("chat.json"))
    }()

    func load() -> ChatTranscript? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ChatTranscript.self, from: data)
        } catch {
            // An unreadable file only costs the old chat; start clean rather than fail.
            Self.log.error("Chat file unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ transcript: ChatTranscript) {
        do {
            try JSONEncoder().encode(transcript)
                .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.log.error("Chat save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
