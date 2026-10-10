import Foundation

/// The daily "log your food" nudge (issue #12, D73): which days get one and at what time.
/// Pure planning; `ReminderScheduler` hands the result to iOS as local notifications, so
/// nothing leaves the phone.
struct ReminderPlan: Equatable, Sendable {
    /// Reminders are scheduled one day at a time so a day that's already logged can be
    /// skipped. They're refreshed whenever the app opens, so they only run out after this
    /// many days without opening it.
    static let daysAhead = 14
    /// 5:00 PM.
    static let defaultMinutes = 17 * 60

    static let title = "Logged today's meals yet?"
    static let body = "Just say what you ate."

    /// Minutes after midnight, 0..<1440.
    var minutes: Int

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    /// The next `daysAhead` days to remind on. Today is left out once something is logged
    /// or the reminder time has passed.
    func days(today: LocalDate, loggedToday: Bool, now: Date, timeZone: TimeZone) -> [LocalDate] {
        let skipToday = loggedToday || now >= fireDate(on: today, in: timeZone)
        return (skipToday ? 1...Self.daysAhead : 0...(Self.daysAhead - 1)).map { today.adding(days: $0) }
    }

    /// When the reminder goes off on `day`, in the app's time zone.
    func fireDate(on day: LocalDate, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                  hour: hour, minute: minute))!
    }

    /// The time as a Date today, for a time picker.
    func pickerDate(in timeZone: TimeZone, now: Date = Date()) -> Date {
        fireDate(on: LocalDate.today(in: timeZone, now: now), in: timeZone)
    }

    /// Reads the hour and minute back out of a time picker's Date.
    static func minutes(from date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 17) * 60 + (c.minute ?? 0)
    }

    /// "5:00 PM", in the user's locale.
    func timeText(in timeZone: TimeZone) -> String {
        pickerDate(in: timeZone).formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }
}
