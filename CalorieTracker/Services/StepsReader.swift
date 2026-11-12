import Foundation
import HealthKit

// Shared with the widget extension (#16, D95). The widget reads steps itself, using the
// permission the app was given; the app reads them too whenever it opens, to keep the
// cached reading fresh for when the phone is locked. Steps are shown only in the widget
// and never sent to Anthropic.

enum StepsReader {
    static let stepCount = HKQuantityType(.stepCount)

    /// Today's steps so far, or nil when Health can't be read right now (the phone is
    /// locked, or there's no Health on this device).
    static func today(in timeZone: TimeZone, now: Date = Date(), store: HKHealthStore = HKHealthStore()) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let since = calendar.startOfDay(for: now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepCount,
                                       predicate: HKQuery.predicateForSamples(withStart: since, end: nil)),
            options: .cumulativeSum)
        do {
            let sum = try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            return Int(sum.rounded())
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        } catch {
            return nil
        }
    }

    /// False until the app has asked for Steps. (iOS never says whether reading was allowed;
    /// a "no" just reads as zero steps.)
    static func hasAsked(store: HKHealthStore = HKHealthStore()) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [stepCount])
        return status != .shouldRequest
    }

    /// Reads today's steps and keeps them for the widget. Returns what the widget should show.
    @discardableResult
    static func refresh(timeZone: TimeZone, now: Date = Date(),
                        defaults: UserDefaults? = WidgetShare.defaults) async -> StepsShown {
        let today = LocalDate.today(in: timeZone, now: now)
        let asked = await hasAsked()
        let fresh = asked ? await self.today(in: timeZone, now: now) : nil
        if let fresh { WidgetShare.writeSteps(StepsReading(day: today, count: fresh), to: defaults) }
        return StepsShown.pick(fresh: fresh, cached: WidgetShare.readSteps(from: defaults), today: today, asked: asked)
    }
}
