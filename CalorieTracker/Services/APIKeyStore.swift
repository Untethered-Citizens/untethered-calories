import Foundation
import Security

/// The user's Anthropic API key, kept in the Keychain and nowhere else:
/// never in UserDefaults, SwiftData, files or logs.
///
/// Stored "this device only, after first unlock": it is not synced to iCloud Keychain
/// and does not move to another phone through a backup. It stays readable after the
/// first unlock so a background task could use it later.
struct APIKeyStore {
    enum Failure: Error, Equatable {
        case keychain(OSStatus)
        case empty
    }

    private let service: String
    private let account: String

    init(service: String = Bundle.main.bundleIdentifier ?? "calorietracker",
         account: String = "anthropic-api-key") {
        self.service = service
        self.account = account
    }

    /// The stored key, or nil if there is none.
    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var hasKey: Bool { (try? load()) != nil }

    /// Saves the key, replacing any existing one. Surrounding whitespace from a paste is trimmed.
    func save(_ key: String) throws {
        let cleaned = APIKeyStore.clean(key)
        guard !cleaned.isEmpty else { throw Failure.empty }
        let data = Data(cleaned.utf8)

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.keychain(status) }

        var add = baseQuery
        add.merge(update) { _, new in new }
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
    }

    /// Removes the key. Removing a key that isn't there is not an error.
    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Trims whitespace and newlines a paste often carries.
    static func clean(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the text looks like an Anthropic key. Only a hint for the UI;
    /// the validation call is what decides.
    static func looksLikeAnthropicKey(_ key: String) -> Bool {
        let cleaned = clean(key)
        return cleaned.hasPrefix("sk-ant-") && cleaned.count > 20 && !cleaned.contains(where: \.isWhitespace)
    }

    /// A safe way to show which key is stored: "sk-ant-…WXYZ". Never show the full key.
    static func masked(_ key: String) -> String {
        let cleaned = clean(key)
        guard cleaned.count > 11 else { return "••••" }
        return "\(cleaned.prefix(7))…\(cleaned.suffix(4))"
    }
}
