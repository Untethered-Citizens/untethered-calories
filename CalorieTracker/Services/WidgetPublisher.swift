import Foundation
import SwiftData
import WidgetKit

/// Keeps the Home Screen widget's snapshot current (D93). Called on launch, on every return
/// to the foreground, at midnight and after every save, so the widget matches the Today tab.
enum WidgetPublisher {
    /// Today's numbers, from the same deterministic totals the dashboard uses.
    static func snapshot(today: LocalDate, timeZone: TimeZone, in context: ModelContext) throws -> WidgetSnapshot {
        let eaten = try DayTotalsIndex.load(from: today, through: today, in: context)[today] ?? .zero
        return WidgetSnapshot(day: today, timeZoneID: timeZone.identifier,
                              target: try TargetStore.current(on: today, in: context).calories,
                              eaten: eaten.calories,
                              nextTarget: try TargetStore.current(on: today.adding(days: 1), in: context).calories)
    }

    /// Writes the snapshot and asks the widget to redraw if anything changed.
    static func publish(in context: ModelContext, settings: AppSettings = AppSettings(),
                        defaults: UserDefaults? = WidgetShare.defaults, now: Date = Date()) {
        let timeZone = settings.timeZone
        guard let snapshot = try? snapshot(today: LocalDate.today(in: timeZone, now: now),
                                           timeZone: timeZone, in: context) else { return }
        if WidgetShare.write(snapshot, to: defaults) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetShare.caloriesKind)
        }
    }
}
