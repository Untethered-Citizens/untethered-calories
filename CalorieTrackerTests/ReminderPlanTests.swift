import Foundation
import Testing
@testable import CalorieTracker

struct ReminderPlanTests {
    let zone = TimeZone(identifier: "America/Denver")!
    let today = LocalDate(iso: "2026-10-10")!
    let plan = ReminderPlan(minutes: ReminderPlan.defaultMinutes)

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute))!
    }

    @Test func defaultsToFivePM() {
        #expect(plan.hour == 17 && plan.minute == 0)
    }

    @Test func remindsTodayWhenNothingLoggedYet() {
        let days = plan.days(today: today, loggedToday: false, now: at(9), timeZone: zone)
        #expect(days.first == today)
        #expect(days.count == ReminderPlan.daysAhead)
    }

    @Test func skipsTodayOnceSomethingIsLogged() {
        let days = plan.days(today: today, loggedToday: true, now: at(9), timeZone: zone)
        #expect(days.first == today.adding(days: 1))
        #expect(days.count == ReminderPlan.daysAhead)
    }

    @Test func skipsTodayWhenTheTimeHasPassed() {
        let days = plan.days(today: today, loggedToday: false, now: at(17), timeZone: zone)
        #expect(days.first == today.adding(days: 1))
    }

    @Test func fireDateIsInTheAppTimeZone() {
        #expect(plan.fireDate(on: today, in: zone) == at(17))
    }

    @Test func pickerRoundTripsMinutes() {
        let half = ReminderPlan(minutes: 20 * 60 + 30)
        #expect(ReminderPlan.minutes(from: half.pickerDate(in: zone, now: at(9)), in: zone) == 20 * 60 + 30)
    }

    @Test func settingsDefaultOffAtFiveAndClampTime() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "ReminderPlanTests-\(UUID())")!)
        #expect(!settings.reminderEnabled)
        #expect(!settings.reminderOffered)
        #expect(settings.reminderMinutes == 17 * 60)
        settings.reminderMinutes = 0
        #expect(settings.reminderMinutes == 0)
        settings.reminderMinutes = 5000
        #expect(settings.reminderMinutes == 1439)
    }
}
