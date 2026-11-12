import SwiftUI
import WidgetKit

/// The Home Screen widget (#5): today's calories left, in the app's look. Tapping it opens
/// the Log tab, ready to type (D94). Every number comes from the app's snapshot (D93).
struct CaloriesLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShare.caloriesKind, provider: CaloriesProvider()) { entry in
            CaloriesLeftView(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
                .widgetURL(WidgetLink.log)
        }
        .configurationDisplayName("Calories left")
        .description("How many calories you have left today. Tap to log what you ate.")
        .supportedFamilies([.systemSmall])
    }
}

struct CaloriesEntry: TimelineEntry {
    var date: Date
    /// Nil until the app has written its first snapshot (before onboarding, or never opened).
    var value: CaloriesLeft?

    static let sample = CaloriesEntry(date: Date(), value: CaloriesLeft(day: LocalDate.today(), left: 1_240))
}

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        let now = Date()
        completion(WidgetShare.read().map { CaloriesEntry(date: now, value: $0.display(at: now)) } ?? .sample)
    }

    /// Now, then each midnight ahead, so a new day starts from its full target without the app.
    /// The app asks for a new timeline whenever the numbers change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let now = Date()
        guard let snapshot = WidgetShare.read() else {
            completion(Timeline(entries: [CaloriesEntry(date: now, value: nil)], policy: .never))
            return
        }
        let entries = snapshot.timeline(from: now).map { CaloriesEntry(date: $0.date, value: $0.value) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct CaloriesLeftView: View {
    var entry: CaloriesEntry

    var body: some View {
        if let value = entry.value {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today")
                    .font(.custom(WidgetStyle.label, size: 15))
                    .foregroundStyle(WidgetStyle.muted)
                Spacer(minLength: 0)
                Text(value.shown.formatted())
                    .font(.custom(WidgetStyle.number, size: 56).monospacedDigit())
                    .foregroundStyle(value.isOver ? WidgetStyle.plum : WidgetStyle.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(value.unit)
                    .font(.custom(WidgetStyle.label, size: 17))
                    .foregroundStyle(WidgetStyle.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value.spoken)
        } else {
            Text("Open Untethered Calories to get started.")
                .font(.custom(WidgetStyle.label, size: 15))
                .foregroundStyle(WidgetStyle.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

#Preview(as: .systemSmall) {
    CaloriesLeftWidget()
} timeline: {
    CaloriesEntry.sample
    CaloriesEntry(date: Date(), value: CaloriesLeft(day: LocalDate.today(), left: -212))
    CaloriesEntry(date: Date(), value: nil)
}
