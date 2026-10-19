import Foundation
import Testing
@testable import CalorieTracker

/// In-app paths into iOS Settings quote what iOS shows: the display name, not "Untethered" (D70, issue #31).
@MainActor
struct HealthWeightTextTests {
    @Test func accessPathEndsWithTheDisplayName() throws {
        let displayName = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        #expect(HealthWeight.accessPath.hasSuffix("Health → \(displayName)"))
    }

    @Test func messagesUseTheAccessPath() {
        let messages = [HealthWeight.noReadingsHelp, HealthWeight.SaveError.notAllowed.errorDescription ?? ""]
        for message in messages {
            #expect(message.contains(HealthWeight.accessPath))
            #expect(!message.contains("→ Untethered"))
        }
    }
}
