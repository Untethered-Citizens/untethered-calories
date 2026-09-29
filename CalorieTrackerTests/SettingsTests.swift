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
        #expect(s.weightUnit == .lb)
        #expect(!s.hasCompletedOnboarding)
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
        s.weightUnit = .kg
        #expect(s.weightUnit == .kg)
        s.hasCompletedOnboarding = true
        #expect(s.hasCompletedOnboarding)
    }

    @Test func weightUnitConversion() {
        #expect(abs(WeightUnit.kg.fromPounds(171.6) - 77.84) < 0.01)
        #expect(abs(WeightUnit.kg.toPounds(WeightUnit.kg.fromPounds(171.6)) - 171.6) < 1e-9)
        #expect(WeightUnit.lb.fromPounds(171.6) == 171.6)
    }
}
