import Foundation
import HealthKit
import OSLog
import SwiftData

/// Reads weight from Apple Health, and saves the weights the user types in (D50). Health is
/// the one place weight lives; the app keeps a copy per day.
///
/// iOS never tells an app whether reading was allowed. A "no" looks exactly like having no
/// weights, so the UI can only say where to change it, not whether it's off. Saving is
/// different: iOS does say whether that was allowed.
@MainActor @Observable
final class HealthWeight {
    /// False on devices without Health, such as some iPads.
    let isAvailable = HKHealthStore.isHealthDataAvailable()
    /// True until the permission sheet has been shown once. After that iOS won't show it again.
    private(set) var needsRequest = true

    /// Shown when access was asked for but no weights have arrived.
    static let noReadingsHelp = "No weights in the last 90 days. Tap Add weight, or weigh in on a smart scale that saves to Apple Health. If you've weighed in and nothing shows, check access: Settings → Privacy & Security → Health → Untethered, and turn on Weight."

    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private var syncing = false
    private static let log = Logger(subsystem: "com.frees321.calorietracker", category: "health")

    func refreshStatus() async {
        guard isAvailable else { return }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: [bodyMass])
            needsRequest = status != .unnecessary
        } catch {
            Self.log.error("Health status failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows the permission sheet (read, and save for typed-in weights), then brings weights in.
    func connect(into context: ModelContext, today: LocalDate, timeZone: TimeZone) async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
        } catch {
            Self.log.error("Health request failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshStatus()
        await sync(into: context, today: today, timeZone: timeZone)
    }

    enum SaveError: LocalizedError {
        case notAllowed

        var errorDescription: String? {
            "Untethered Calories isn't allowed to save weight to Apple Health. To allow it: Settings → Privacy & Security → Health → Untethered, and turn on Weight under the apps allowed to write data."
        }
    }

    /// Saves a typed-in weight to Health, asking first if saving hasn't been asked about,
    /// then syncs so it shows straight away.
    func save(_ value: Double, unit: WeightUnit, at date: Date,
              into context: ModelContext, today: LocalDate, timeZone: TimeZone) async throws {
        // Ask whenever iOS would show a sheet. Checking `authorizationStatus` for
        // `.notDetermined` isn't enough: after a read-only request it already reports denied.
        if try await store.statusForAuthorizationRequest(toShare: [bodyMass], read: [bodyMass]) == .shouldRequest {
            try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
        }
        guard store.authorizationStatus(for: bodyMass) == .sharingAuthorized else { throw SaveError.notAllowed }
        let quantity = HKQuantity(unit: unit == .lb ? .pound() : .gramUnit(with: .kilo), doubleValue: value)
        try await store.save(HKQuantitySample(type: bodyMass, quantity: quantity, start: date, end: date))
        await sync(into: context, today: today, timeZone: timeZone)
    }

    /// Reads the window's weigh-ins and writes one per day. Runs only after the user has
    /// been asked, so it never triggers a permission sheet by itself.
    func sync(into context: ModelContext, today: LocalDate, timeZone: TimeZone) async {
        await refreshStatus()
        guard isAvailable, !needsRequest, !syncing else { return }
        syncing = true
        defer { syncing = false }

        let start = WeightImport.windowStart(today: today)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let since = calendar.startOfDay(for: start.date(in: timeZone))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass,
                                         predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            let samples = try await descriptor.result(for: store).map {
                WeightSample(taken: $0.startDate, pounds: $0.quantity.doubleValue(for: .pound()))
            }
            let daily = WeightImport.dailyLatest(samples, in: timeZone)
            let changed = try WeightSync.apply(daily, from: start, through: today, in: context)
            Self.log.debug("Health sync: \(samples.count) samples, \(changed) days changed")
        } catch {
            // Health data is locked while the phone is locked; the next foreground retries.
            Self.log.error("Health sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
