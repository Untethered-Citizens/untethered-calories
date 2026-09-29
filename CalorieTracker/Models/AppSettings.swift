import Foundation

/// Small preferences kept in UserDefaults. The API key is never here: it lives in the Keychain.
struct AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let detailWindowDays = "detailWindowDays"
        static let summaryRetentionDays = "summaryRetentionDays"
        static let transcriptRetentionDays = "transcriptRetentionDays"
        static let modelID = "modelID"
        static let timeZoneID = "timeZoneID"
        static let weightUnit = "weightUnit"
    }

    /// How weight is shown. Stored weights are always lb; this only changes display.
    var weightUnit: WeightUnit {
        get { defaults.string(forKey: Key.weightUnit).flatMap(WeightUnit.init(rawValue:)) ?? .lb }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.weightUnit) }
    }

    /// Days of meal-level detail kept before roll-up (D13).
    var detailWindowDays: Int {
        get { positive(Key.detailWindowDays) ?? 14 }
        nonmutating set { defaults.set(max(1, newValue), forKey: Key.detailWindowDays) }
    }

    /// Days of daily summaries kept. Nil means forever.
    var summaryRetentionDays: Int? {
        get { defaults.object(forKey: Key.summaryRetentionDays) == nil ? 365 : positive(Key.summaryRetentionDays) }
        nonmutating set { defaults.set(newValue ?? 0, forKey: Key.summaryRetentionDays) }
    }

    var transcriptRetentionDays: Int {
        get { positive(Key.transcriptRetentionDays) ?? 7 }
        nonmutating set { defaults.set(max(1, newValue), forKey: Key.transcriptRetentionDays) }
    }

    /// The Claude model to call. Nil until chosen from the live model list (never hard-coded).
    var modelID: String? {
        get { defaults.string(forKey: Key.modelID) }
        nonmutating set { defaults.set(newValue, forKey: Key.modelID) }
    }

    /// The time zone that defines "a day". Defaults to the device's.
    var timeZone: TimeZone {
        get { defaults.string(forKey: Key.timeZoneID).flatMap(TimeZone.init(identifier:)) ?? .current }
        nonmutating set { defaults.set(newValue.identifier, forKey: Key.timeZoneID) }
    }

    private func positive(_ key: String) -> Int? {
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }
}
