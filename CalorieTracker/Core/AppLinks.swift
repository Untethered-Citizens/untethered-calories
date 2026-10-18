import Foundation

/// The companion website's pages, linked from Settings → About.
/// Plain URLs with no query string, so nothing about the visit is tracked.
enum AppLinks {
    static let website = URL(string: "https://untetheredcalories.com/")!
    static let privacy = URL(string: "https://untetheredcalories.com/privacy/")!
    static let support = URL(string: "https://untetheredcalories.com/support/")!

    static let all = [website, privacy, support]

    /// "1.0 (12)" from the bundle, for support requests.
    static func versionText(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
