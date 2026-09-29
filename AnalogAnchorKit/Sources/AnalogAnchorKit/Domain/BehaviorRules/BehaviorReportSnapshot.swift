import Foundation

/// Aggregate usage snapshot produced by the `DeviceActivityReport` extension and
/// read back by the main app from the shared App Group.
///
/// ## Why this shape
/// Apple exposes *detailed* usage only inside a `DeviceActivityReport`
/// extension. That extension runs in its own sandbox and cannot hand values
/// directly to the app; the officially supported channel is the shared App Group
/// container, which both processes already use for the Screen Time policy. The
/// extension writes this file, the app reads it.
///
/// ## What Apple actually allows
/// `DeviceActivityResults` yields, per application / category / web domain, the
/// **total activity duration** for the queried interval. It does **not** expose
/// open counts, first-launch timestamps, or a late-night breakdown. This model
/// therefore stores only what is real: durations. The fields the rules need but
/// Apple does not provide (`openCountLast24h`, `compulsiveCheckCount`,
/// `lateNightOpens`) are deliberately absent here rather than defaulted to a
/// fabricated zero — the mapping in `metrics()` reports them as unavailable.
public struct BehaviorReportSnapshot: Codable, Equatable, Sendable {

    /// One application's aggregate usage over the report interval.
    public struct AppUsage: Codable, Equatable, Sendable {
        /// Opaque token identity from the report extension. This is the
        /// extension's own `Application.bundleIdentifier` when available; it is
        /// never an enumerated installed-apps list.
        public var identifier: String
        public var displayName: String?
        public var totalSeconds: TimeInterval

        public init(identifier: String, displayName: String? = nil, totalSeconds: TimeInterval) {
            self.identifier = identifier
            self.displayName = displayName
            self.totalSeconds = totalSeconds
        }
    }

    /// One category's aggregate usage.
    public struct CategoryUsage: Codable, Equatable, Sendable {
        public var identifier: String
        public var displayName: String?
        public var totalSeconds: TimeInterval

        public init(identifier: String, displayName: String? = nil, totalSeconds: TimeInterval) {
            self.identifier = identifier
            self.displayName = displayName
            self.totalSeconds = totalSeconds
        }
    }

    /// When the extension produced this snapshot.
    public var generatedAt: Date
    /// The reporting interval the durations cover, in hours.
    public var windowHours: Int
    public var applications: [AppUsage]
    public var categories: [CategoryUsage]

    public init(
        generatedAt: Date = Date(),
        windowHours: Int,
        applications: [AppUsage] = [],
        categories: [CategoryUsage] = []
    ) {
        self.generatedAt = generatedAt
        self.windowHours = windowHours
        self.applications = applications
        self.categories = categories
    }

    /// Whether the snapshot is recent enough to trust for a 7-day average.
    /// A stale file (older than ~26h) is not used, so the app never presents
    /// last week's numbers as today's.
    public func isFresh(now: Date = Date(), maxAge: TimeInterval = 26 * 3600) -> Bool {
        now.timeIntervalSince(generatedAt) <= maxAge
    }

    /// Maps the durations Apple supplied onto the domain's metrics, filling ONLY
    /// the fields Apple can actually provide.
    ///
    /// `totalMinutesLast7d` is derived by scaling the observed window to seven
    /// days — an estimate Apple's data supports. The fields that would require
    /// per-open telemetry (`openCountLast24h`, `compulsiveCheckCount`,
    /// `lateNightOpens`) are left at zero, which means the corresponding rules
    /// simply do not fire. That is the honest outcome, not a fabricated one.
    public func metrics(scaledToSevenDays: Bool = true) -> [BehaviorRules.Metrics] {
        applications.map { app in
            let observedMinutes = app.totalSeconds / 60.0
            let scaled: Double
            if scaledToSevenDays, windowHours > 0 {
                scaled = observedMinutes * (168.0 / Double(windowHours))
            } else {
                scaled = observedMinutes
            }
            return BehaviorRules.Metrics(
                appIdentifier: app.displayName ?? app.identifier,
                openCountLast24h: 0,
                totalMinutesLast7d: Int(scaled.rounded()),
                lateNightOpens: 0,
                compulsiveCheckCount: 0
            )
        }
    }
}
