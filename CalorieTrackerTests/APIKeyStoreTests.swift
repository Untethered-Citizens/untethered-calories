import Foundation
import Testing
@testable import CalorieTracker

/// Uses the simulator's real Keychain under a throwaway account, so it never touches the app's key.
@Suite(.serialized)
struct APIKeyStoreTests {
    let store = APIKeyStore(account: "test-\(UUID().uuidString)")
    let fakeKey = "sk-ant-test-0000000000000000000000WXYZ"

    @Test func emptyUntilSaved() throws {
        #expect(try store.load() == nil)
        #expect(!store.hasKey)
    }

    @Test func saveLoadReplaceDelete() throws {
        defer { try? store.delete() }
        try store.save("  \(fakeKey)\n")
        #expect(try store.load() == fakeKey)
        try store.save("sk-ant-test-replacement-111111111111")
        #expect(try store.load() == "sk-ant-test-replacement-111111111111")
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete() // deleting again is fine
    }

    @Test func blankKeyIsRejected() {
        #expect(throws: APIKeyStore.Failure.empty) { try store.save("   \n") }
    }

    @Test func formatHintAndMasking() {
        #expect(APIKeyStore.looksLikeAnthropicKey(" \(fakeKey) "))
        #expect(!APIKeyStore.looksLikeAnthropicKey("hello"))
        #expect(!APIKeyStore.looksLikeAnthropicKey("sk-ant-with a space-00000000000"))
        #expect(APIKeyStore.masked(fakeKey) == "sk-ant-…WXYZ")
        #expect(!APIKeyStore.masked(fakeKey).contains("0000"))
        #expect(APIKeyStore.masked("short") == "••••")
    }
}
