import Foundation
import AnalogAnchorKit

#if canImport(DeviceActivity)
import DeviceActivity
#endif

#if canImport(FamilyControls)
import FamilyControls
#endif

/// Behavior metrics provider backed by the real `DeviceActivityReport` extension.
///
/// ## The data path (no fabrication)
/// ```
/// DeviceActivityReport extension  →  BehaviorReportSnapshot (App Group)
///         →  BehaviorReportProvider  →  BehaviorRuleEvaluation  →  BehaviorRules
/// ```
///
/// Apple never lets the app process read raw usage, so this provider reads only
/// the aggregate snapshot the extension wrote. When that snapshot is missing,
/// stale, or Screen Time is not authorized, `isAvailable` is `false` and
/// `metrics()` returns nothing — the rules then simply do not fire. Nothing is
/// invented.
@MainActor
final class BehaviorReportProvider: BehaviorMetricsProvider {

    private let store: SharedPolicyStore
    private let isAuthorized: () -> Bool

    init(
        store: SharedPolicyStore = SharedPolicyStore(),
        isAuthorized: @escaping () -> Bool
    ) {
        self.store = store
        self.isAuthorized = isAuthorized
    }

    /// Whether a fresh, real report exists to evaluate against.
    var isAvailable: Bool {
        guard isAuthorized() else { return false }
        guard let snapshot = store.loadBehaviorReport() else { return false }
        return snapshot.isFresh()
    }

    /// The raw snapshot, for diagnostics display (never raw identifiers).
    func currentSnapshot() -> BehaviorReportSnapshot? {
        store.loadBehaviorReport()
    }

    /// Nonisolated conformance: hop to the main actor to read the store.
    nonisolated func metrics() async -> [BehaviorRules.Metrics] {
        await MainActor.run {
            guard isAvailable, let snapshot = store.loadBehaviorReport() else { return [] }
            return snapshot.metrics()
        }
    }
}

/// Builds the `DeviceActivityReport` filter that drives the report extension.
///
/// Rendering a `DeviceActivityReport` scene is what causes Apple to run the
/// extension; the app cannot pull the numbers any other way.
enum BehaviorReportFilter {

    /// The context string must match the extension's `DeviceActivityReport.Context`.
    static let contextName = "Analog Anchor Usage"

    #if canImport(DeviceActivity) && canImport(FamilyControls)
    static func today() -> DeviceActivityFilter {
        // The last 24 hours, matching `BehaviorUsageReport.windowHours`.
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }
    #endif
}
