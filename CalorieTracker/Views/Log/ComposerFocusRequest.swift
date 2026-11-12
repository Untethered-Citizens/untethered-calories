import Observation

/// A one-shot request to put the cursor in the Log composer, set when the widget opens the
/// app (D94). It waits until the Log screen is there to take it, which on a cold launch is
/// after the tab has been built.
@Observable
final class ComposerFocusRequest {
    private(set) var pending = false

    func request() { pending = true }

    /// True once per request.
    func take() -> Bool {
        guard pending else { return false }
        pending = false
        return true
    }
}
