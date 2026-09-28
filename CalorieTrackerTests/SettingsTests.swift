import Foundation
import Testing
@testable import CalorieTracker

struct SettingsTests {
    func fresh() -> AppSettings {
        let name = "test-\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: name)!)
    }

    @Test func defaults() {
        let s = fresh()
        #expect(s.detailWindowDays == 14)
        #expect(s.summaryRetentionDays == 365)
        #expect(s.transcriptRetentionDays == 7)
        #expect(s.modelID == nil)
        #expect(s.timeZone == .current)
    }

    @Test func roundTrips() {
        let s = fresh()
        s.detailWindowDays = 30
        s.summaryRetentionDays = nil
        s.modelID = "some-model"
        s.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(s.detailWindowDays == 30)
        #expect(s.summaryRetentionDays == nil)
        #expect(s.modelID == "some-model")
        #expect(s.timeZone.identifier == "America/Los_Angeles")
        s.detailWindowDays = 0
        #expect(s.detailWindowDays == 1)
    }
}
