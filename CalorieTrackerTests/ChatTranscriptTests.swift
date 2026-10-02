import Foundation
import Testing
@testable import CalorieTracker

struct ChatTranscriptTests {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let today = LocalDate(iso: "2026-10-02")!

    func at(_ daysAgo: Int) -> Date { today.adding(days: -daysAgo).date(in: zone) }

    func item(_ kind: LogConversation.Item.Kind, daysAgo: Int) -> ChatTranscript.StoredItem {
        ChatTranscript.StoredItem(LogConversation.Item(kind: kind, at: at(daysAgo)))
    }

    @Test func keepsTheLastNCalendarDaysIncludingToday() {
        let transcript = ChatTranscript(items: [
            item(.user("old", photos: []), daysAgo: 7),
            item(.user("kept", photos: []), daysAgo: 6),
            item(.user("today", photos: []), daysAgo: 0),
        ], proposals: [:])
        let kept = transcript.pruned(keepingDays: 7, today: today, timeZone: zone)
        #expect(kept.items.map(\.text) == ["kept", "today"])
    }

    @Test func dropsCardsNoLongerShownAndStrayDividers() {
        let gone = UUID(), shown = UUID()
        let proposal = { (id: UUID) in
            LogConversation.Proposal(id: id, kind: .targets(.defaults, from: today, goalNote: ""))
        }
        let transcript = ChatTranscript(items: [
            item(.proposal(gone), daysAgo: 10),
            item(.newConversation, daysAgo: 2),
            item(.proposal(shown), daysAgo: 1),
            item(.newConversation, daysAgo: 1),
            item(.newConversation, daysAgo: 0),
        ], proposals: [gone: proposal(gone), shown: proposal(shown)])
        let kept = transcript.pruned(keepingDays: 7, today: today, timeZone: zone)
        #expect(kept.items.map(\.kind) == [.proposal])
        #expect(Array(kept.proposals.keys) == [shown])
    }

    @Test func roundTripsThroughTheFile() throws {
        let store = ChatStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID()).json"))
        defer { store.delete() }
        store.save(ChatTranscript(items: [item(.logged("Logged: Apple, 95 cal"), daysAgo: 0)], proposals: [:]))
        let loaded = try #require(store.load())
        #expect(loaded.items.first?.text == "Logged: Apple, 95 cal")
        #expect(loaded.items.first?.kind == .logged)
    }
}
