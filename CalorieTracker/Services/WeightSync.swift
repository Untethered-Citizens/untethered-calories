import Foundation
import SwiftData

/// Writes Health weights into the daily rows. Health is the source of truth inside the
/// window: a reading there sets that day's weight, and a Health weight that has since been
/// deleted or changed in Health is corrected here. Weights from anywhere else are left alone,
/// and so is anything older than the window.
enum WeightSync {
    /// Returns how many days changed.
    @discardableResult
    static func apply(_ daily: [LocalDate: Double], from start: LocalDate, through today: LocalDate,
                      in context: ModelContext) throws -> Int {
        var changed = 0
        for (day, pounds) in daily where day >= start && day <= today {
            let row = try DailySummaryStore.getOrCreate(day, in: context)
            if row.weight != pounds || !row.weightFromHealth {
                row.weight = pounds
                row.weightFromHealth = true
                changed += 1
            }
        }

        let lo = start.iso, hi = today.iso
        let fromHealth = try context.fetch(FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.weightFromHealth && $0.dayKey >= lo && $0.dayKey <= hi }))
        for row in fromHealth where daily[row.date] == nil {
            row.weight = nil
            row.weightFromHealth = false
            changed += 1
        }

        if changed > 0 { try context.save() }
        return changed
    }
}
