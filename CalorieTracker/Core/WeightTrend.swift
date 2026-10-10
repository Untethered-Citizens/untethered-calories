import Foundation

/// One weight reading, in pounds (D29).
struct WeightReading: Equatable, Sendable {
    var day: LocalDate
    var pounds: Double
}

/// Weight readings with the honest 7-day average: drawn only where the trailing seven days
/// hold at least four readings, so a sparse week shows a gap instead of a made-up line.
struct WeightSeries: Equatable, Sendable {
    static let windowDays = 7
    static let minimumReadings = 4

    struct Point: Equatable, Sendable {
        var day: LocalDate
        var pounds: Double
    }

    /// Oldest first.
    let readings: [WeightReading]
    /// From the first logged day (meals or weight) through today, so gaps are visible.
    let span: [LocalDate]
    /// Stretches of the moving average with no gaps inside. A new stretch starts after any
    /// day that didn't qualify, so the line is never drawn across a gap.
    let averageRuns: [[Point]]

    init(readings: [WeightReading], firstLoggingDay: LocalDate?, today: LocalDate) {
        self.readings = readings.sorted { $0.day < $1.day }
        let start = [firstLoggingDay, self.readings.first?.day].compactMap { $0 }.min() ?? today
        span = LocalDate.range(from: min(start, today), through: today)

        var runs: [[Point]] = []
        var current: [Point] = []
        for day in span {
            let from = day.adding(days: -(Self.windowDays - 1))
            let window = self.readings.filter { $0.day >= from && $0.day <= day }
            if window.count >= Self.minimumReadings {
                current.append(Point(day: day, pounds: window.map(\.pounds).reduce(0, +) / Double(window.count)))
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        averageRuns = runs
    }

    var latest: WeightReading? { readings.last }
    var first: WeightReading? { readings.first }

    /// Latest minus first, to one decimal. Negative is a loss.
    var change: Double? {
        guard let latest, let first else { return nil }
        return ((latest.pounds - first.pounds) * 10).rounded() / 10
    }

    /// True once there's a line to read, not just dots.
    var hasTrend: Bool { averageRuns.contains { $0.count > 1 } }

    /// The average on a given day, if that day qualifies.
    func average(on day: LocalDate) -> Double? {
        averageRuns.lazy.flatMap { $0 }.first { $0.day == day }?.pounds
    }
}

/// When the Trend tab has enough to say something true: about three weeks of intake,
/// and enough weigh-ins for the 7-day average to run across them (D47).
struct TrendGate: Equatable, Sendable {
    static let intakeDaysNeeded = 21
    static let readingsNeeded = 12

    var intakeDays: Int
    var readings: Int

    var isUnlocked: Bool { intakeDays >= Self.intakeDaysNeeded && readings >= Self.readingsNeeded }

    /// Progress lines for the locked card. A met requirement says so, never "16 of 12".
    var intakeLine: String {
        intakeDays >= Self.intakeDaysNeeded
            ? "Intake: ✓ \(intakeDays) days logged — enough"
            : "Intake: \(intakeDays) of \(Self.intakeDaysNeeded) days logged"
    }

    var weightLine: String {
        readings >= Self.readingsNeeded
            ? "Weight: ✓ \(readings) readings — enough"
            : "Weight: \(readings) of \(Self.readingsNeeded) readings"
    }
}

/// What intake and the weight trend together imply, over the stretch where both exist.
/// A rough guide: about 3,500 kcal per pound, and logging and water both add noise.
struct EnergyBalance: Equatable, Sendable {
    static let caloriesPerPound = 3500.0
    /// Shorter stretches are mostly water and logging noise.
    static let minimumDays = 14

    let from: LocalDate
    let through: LocalDate
    /// Average calories over the days that have intake data. Gaps aren't averaged over.
    let averageIntake: Int
    let loggedDays: Int
    /// Change in the 7-day average weight across the stretch. Negative is a loss.
    let poundsChange: Double
    /// Calories a day the weight change implies, below (negative) or above intake.
    let impliedDailyBalance: Int
    /// Intake minus the implied balance: roughly what the body used each day.
    let estimatedMaintenance: Int

    /// Uses the first and last days, before today, that have a weight average over a full
    /// seven-day window, so both ends lag by the same amount. Nil when there isn't a long
    /// enough stretch or no intake in it.
    init?(series: WeightSeries, dayTotals: [LocalDate: NutritionTotals], today: LocalDate) {
        guard let firstDay = series.span.first else { return nil }
        let fullWindow = firstDay.adding(days: WeightSeries.windowDays - 1)
        let points = series.averageRuns.flatMap { $0 }.filter { $0.day >= fullWindow && $0.day < today }
        guard let start = points.first, let end = points.last else { return nil }
        let days = start.day.days(until: end.day)
        guard days >= Self.minimumDays else { return nil }
        let logged = LocalDate.range(from: start.day, through: end.day)
            .compactMap { dayTotals[$0] }.filter { $0.entryCount > 0 }
        guard !logged.isEmpty else { return nil }

        from = start.day
        through = end.day
        loggedDays = logged.count
        let intake = Double(logged.map(\.calories).reduce(0, +)) / Double(logged.count)
        averageIntake = Rounding.nearest5(intake)
        poundsChange = ((end.pounds - start.pounds) * 10).rounded() / 10
        let balance = (end.pounds - start.pounds) * Self.caloriesPerPound / Double(days)
        impliedDailyBalance = Rounding.nearest5(balance)
        estimatedMaintenance = Rounding.nearest5(intake - balance)
    }
}
