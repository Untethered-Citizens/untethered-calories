import Foundation
import SwiftData
import UserNotifications

/// Puts the daily reminder (issue #12, D73) on iOS's own notification schedule. Local
/// notifications only: no server, no push.
@MainActor
enum ReminderScheduler {
    private static let idPrefix = "daily-reminder-"
    private static var center: UNUserNotificationCenter { .current() }

    /// Shows the iOS permission prompt the first time; after that iOS returns the saved answer.
    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// True when notifications for this app are switched off in iOS Settings.
    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Replaces the scheduled reminders with the current plan, skipping today if something
    /// is already logged. Clears them all when the reminder is off.
    static func reschedule(in context: ModelContext, settings: AppSettings = AppSettings(), now: Date = Date()) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard settings.reminderEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let timeZone = settings.timeZone
        let today = LocalDate.today(in: timeZone, now: now)
        let key = today.iso
        let loggedToday = ((try? context.fetchCount(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.dayKey == key }))) ?? 0) > 0
        let plan = ReminderPlan(minutes: settings.reminderMinutes)

        for day in plan.days(today: today, loggedToday: loggedToday, now: now, timeZone: timeZone) {
            var when = DateComponents(year: day.year, month: day.month, day: day.day, hour: plan.hour, minute: plan.minute)
            when.timeZone = timeZone
            let content = UNMutableNotificationContent()
            content.title = ReminderPlan.title
            content.body = ReminderPlan.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: idPrefix + day.iso, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }
}
