import SwiftUI
import WidgetKit

/// The Home Screen widget: today's calories left (#5), today's steps (#16), or both, chosen
/// in its Edit menu. Tapping it opens the Log tab, ready to type (D94). Calorie numbers come
/// from the app's snapshot (D93); steps are read from Apple Health (D95).
struct CaloriesLeftWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShare.caloriesKind, intent: WidgetChoiceIntent.self,
                               provider: CaloriesProvider()) { entry in
            WidgetContent(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
                .widgetURL(WidgetLink.log)
        }
        .configurationDisplayName("Calories left")
        .description("Calories left today, today's steps from Apple Health, or both. Tap to log what you ate.")
        .supportedFamilies([.systemSmall])
    }
}

struct CaloriesEntry: TimelineEntry {
    var date: Date
    var shows: WidgetShows
    /// Nil until the app has written its first snapshot (before onboarding, or never opened).
    var calories: CaloriesLeft?
    var steps: StepsShown

    static func sample(_ shows: WidgetShows = .calories) -> CaloriesEntry {
        CaloriesEntry(date: Date(), shows: shows, calories: CaloriesLeft(day: LocalDate.today(), left: 1_240),
                      steps: .count(6_480))
    }
}

struct CaloriesProvider: AppIntentTimelineProvider {
    /// How often to re-read steps. Widgets get a limited number of refreshes a day.
    static let stepsInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> CaloriesEntry { .sample() }

    func snapshot(for configuration: WidgetChoiceIntent, in context: Context) async -> CaloriesEntry {
        if context.isPreview && WidgetShare.read() == nil { return .sample(configuration.shows) }
        return await entry(for: configuration.shows, at: Date())
    }

    func timeline(for configuration: WidgetChoiceIntent, in context: Context) async -> Timeline<CaloriesEntry> {
        let now = Date()
        let shows = configuration.shows
        let snapshot = WidgetShare.read()
        guard shows.includesSteps else {
            // Calories only: draw now and at each midnight ahead; the app asks for a new
            // timeline whenever the numbers change.
            let entries = snapshot?.timeline(from: now).map {
                CaloriesEntry(date: $0.date, shows: shows, calories: $0.value, steps: .unknown)
            } ?? [CaloriesEntry(date: now, shows: shows, calories: nil, steps: .unknown)]
            return Timeline(entries: entries, policy: .never)
        }
        // Steps change all day, so read again every half hour, and right at midnight.
        let current = await entry(for: shows, at: now)
        var next = now.addingTimeInterval(Self.stepsInterval)
        if let midnight = snapshot?.timeline(from: now, midnights: 1).last?.date, midnight < next { next = midnight }
        return Timeline(entries: [current], policy: .after(next))
    }

    private func entry(for shows: WidgetShows, at now: Date) async -> CaloriesEntry {
        let snapshot = WidgetShare.read()
        let steps: StepsShown = shows.includesSteps
            ? await StepsReader.refresh(timeZone: snapshot?.timeZone ?? .current, now: now)
            : .unknown
        return CaloriesEntry(date: now, shows: shows, calories: snapshot?.display(at: now), steps: steps)
    }
}

struct WidgetContent: View {
    var entry: CaloriesEntry

    var body: some View {
        switch entry.shows {
        case .calories: caloriesOnly
        case .steps: stepsOnly
        case .both: both
        }
    }

    @ViewBuilder private var caloriesOnly: some View {
        if let value = entry.calories {
            Hero(heading: "Today", number: value.shown.formatted(), unit: value.unit,
                 over: value.isOver, spoken: value.spoken)
        } else {
            Note(text: "Open Untethered Calories to get started.")
        }
    }

    @ViewBuilder private var stepsOnly: some View {
        if entry.steps == .notAsked {
            Note(text: "Open Untethered Calories to allow Steps.")
        } else {
            Hero(heading: "Today", number: entry.steps.number, unit: "steps", over: false, spoken: entry.steps.spoken)
        }
    }

    private var both: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today")
                .font(.custom(WidgetStyle.label, size: 15))
                .foregroundStyle(WidgetStyle.muted)
            Spacer(minLength: 4)
            if let value = entry.calories {
                Row(number: value.shown.formatted(), unit: value.unit, over: value.isOver)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(value.spoken)
            } else {
                Row(number: "–", unit: "cal left", over: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Open Untethered Calories to get started")
            }
            Spacer(minLength: 4)
            Row(number: entry.steps.number, unit: entry.steps.unit, over: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.steps.spoken)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// One big number: the calories-only and steps-only layouts.
private struct Hero: View {
    var heading: String
    var number: String
    var unit: String
    var over: Bool
    var spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading)
                .font(.custom(WidgetStyle.label, size: 15))
                .foregroundStyle(WidgetStyle.muted)
            Spacer(minLength: 0)
            Text(number)
                .font(.custom(WidgetStyle.number, size: 56).monospacedDigit())
                .foregroundStyle(over ? WidgetStyle.plum : WidgetStyle.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            Text(unit)
                .font(.custom(WidgetStyle.label, size: 17))
                .foregroundStyle(WidgetStyle.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// A number with its unit beside it, for "Both".
private struct Row: View {
    var number: String
    var unit: String
    var over: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(number)
                .font(.custom(WidgetStyle.number, size: 36).monospacedDigit())
                .foregroundStyle(over ? WidgetStyle.plum : WidgetStyle.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            Text(unit)
                .font(.custom(WidgetStyle.label, size: 14))
                .foregroundStyle(WidgetStyle.muted)
        }
    }
}

private struct Note: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.custom(WidgetStyle.label, size: 15))
            .foregroundStyle(WidgetStyle.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemSmall) {
    CaloriesLeftWidget()
} timeline: {
    CaloriesEntry.sample()
    CaloriesEntry.sample(.steps)
    CaloriesEntry.sample(.both)
    CaloriesEntry(date: Date(), shows: .both, calories: CaloriesLeft(day: LocalDate.today(), left: -212), steps: .unknown)
    CaloriesEntry(date: Date(), shows: .steps, calories: nil, steps: .notAsked)
}
