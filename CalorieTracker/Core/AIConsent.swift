import Foundation

/// Whether the user has allowed the app to send data to Anthropic (App Review 5.1.2(i), issue #28).
/// Nothing reaches the Messages API without `.allowed`.
enum AIConsent: Equatable {
    /// No answer yet, or an Allow given to an older version of the consent screen.
    case unanswered
    case allowed
    /// "Don't allow", or turned off later in Settings.
    case declined

    /// The version of the consent screen's list of what's sent. Raise it whenever the app
    /// starts sending Anthropic something new, so everyone who allowed sees the new list once.
    static let currentVersion = 1

    /// Reads a stored answer. An Allow only counts for the current version or later.
    init(answer: String?, version: Int) {
        switch answer {
        case "allowed" where version >= Self.currentVersion: self = .allowed
        case "declined": self = .declined
        default: self = .unanswered
        }
    }
}
