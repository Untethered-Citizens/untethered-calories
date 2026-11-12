import AppIntents
import WidgetKit

// Shared with the widget extension: the widget uses it for its Edit menu, and the app reads
// it to see whether any widget shows steps (#16).

/// What a placed widget shows.
enum WidgetShows: String, AppEnum {
    case calories, steps, both

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let caseDisplayRepresentations: [WidgetShows: DisplayRepresentation] = [
        .calories: "Calories left",
        .steps: "Steps",
        .both: "Both",
    ]

    var includesSteps: Bool { self != .calories }
    var includesCalories: Bool { self != .steps }
}

/// The widget's Edit menu: Calories left, Steps or Both.
struct WidgetChoiceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose what to show"
    static let description = IntentDescription("Show calories left today, today's steps from Health, or both.")

    @Parameter(title: "Show", default: .calories)
    var shows: WidgetShows

    init() {}
    init(shows: WidgetShows) { self.shows = shows }
}

extension WidgetChoiceIntent {
    /// True when at least one placed widget shows steps.
    static func anyPlacedWidgetShowsSteps() async -> Bool {
        let placed = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        return placed.contains {
            $0.kind == WidgetShare.caloriesKind
                && ($0.widgetConfigurationIntent(of: WidgetChoiceIntent.self)?.shows.includesSteps ?? false)
        }
    }
}
