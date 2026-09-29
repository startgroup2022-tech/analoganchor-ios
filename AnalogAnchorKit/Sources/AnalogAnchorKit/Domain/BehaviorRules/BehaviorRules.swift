import Foundation

/// Behaviour-rule domain, ported from Android's `BehaviorRuleEngine`.
///
/// Android computed these flags from `UsageStats` (open counts, late-night
/// opens, compulsive re-checks, 7-day foreground minutes). iOS has **no**
/// equivalent raw feed: `DeviceActivity` only reports aggregate usage through a
/// `DeviceActivityReport` extension, and that data is not available to the app
/// process. This file therefore carries the *rules and evaluation* (pure, fully
/// testable), while the metrics themselves arrive through
/// `BehaviorMetricsProvider`.
///
/// Nothing here pretends to observe app usage directly.
public enum BehaviorRules {

    public enum FlagType: String, Codable, Sendable {
        case compulsiveChecker = "FLAG_COMPULSIVE_CHECKER"
        case lateNightPattern = "FLAG_LATE_NIGHT_PATTERN"
        case heavyUsage = "FLAG_HEAVY_USAGE"
        case streakReward = "FLAG_STREAK_REWARD"
    }

    public enum Severity: String, Codable, Sendable {
        case info = "INFO"
        case warn = "WARN"
    }

    /// A flag raised by evaluation (`RuleFlag` on Android).
    public struct Flag: Identifiable, Equatable, Codable, Sendable {
        public let id: UUID
        public var flagType: FlagType
        /// Opaque app identifier; `nil` for streak-reward flags.
        public var appIdentifier: String?
        public var severity: Severity
        public var message: String
        public var createdAt: Date

        public init(
            id: UUID = UUID(),
            flagType: FlagType,
            appIdentifier: String? = nil,
            severity: Severity,
            message: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.flagType = flagType
            self.appIdentifier = appIdentifier
            self.severity = severity
            self.message = message
            self.createdAt = createdAt
        }
    }

    /// Per-app metrics for a single evaluation window (`AppBehaviorSnapshot`).
    public struct Metrics: Identifiable, Equatable, Sendable {
        /// Opaque app identifier (Android used a package name; iOS must not).
        public var appIdentifier: String
        public var openCountLast24h: Int
        public var totalMinutesLast7d: Int
        public var lateNightOpens: Int
        public var compulsiveCheckCount: Int

        public var id: String { appIdentifier }

        public init(
            appIdentifier: String,
            openCountLast24h: Int = 0,
            totalMinutesLast7d: Int = 0,
            lateNightOpens: Int = 0,
            compulsiveCheckCount: Int = 0
        ) {
            self.appIdentifier = appIdentifier
            self.openCountLast24h = openCountLast24h
            self.totalMinutesLast7d = totalMinutesLast7d
            self.lateNightOpens = lateNightOpens
            self.compulsiveCheckCount = compulsiveCheckCount
        }
    }

    /// Thresholds, exactly as in `evaluatePackageRules`.
    public enum Thresholds {
        public static let compulsiveOpenCount = 8
        public static let compulsiveRapidChecks = 3
        public static let lateNightOpens = 3
        public static let heavyDailyAverageMinutes = 90
        public static let streakRewardDays = 7
    }

    /// Ports `evaluatePackageRules` for one app.
    public static func evaluate(_ metrics: Metrics, friendlyName: (String) -> String = { $0 }) -> [Flag] {
        var flags: [Flag] = []
        let appName = friendlyName(metrics.appIdentifier)

        if metrics.openCountLast24h >= Thresholds.compulsiveOpenCount
            && metrics.compulsiveCheckCount >= Thresholds.compulsiveRapidChecks {
            flags.append(Flag(
                flagType: .compulsiveChecker,
                appIdentifier: metrics.appIdentifier,
                severity: .warn,
                message: "\(appName) was opened \(metrics.openCountLast24h) times today, including \(metrics.compulsiveCheckCount) rapid repeat checks. Add this context to unlock reviews."
            ))
        }

        if metrics.lateNightOpens >= Thresholds.lateNightOpens {
            flags.append(Flag(
                flagType: .lateNightPattern,
                appIdentifier: metrics.appIdentifier,
                severity: .warn,
                message: "Late-night \(appName) use was detected \(metrics.lateNightOpens) times in the last 3 days."
            ))
        }

        let dailyAverage = Int((Double(metrics.totalMinutesLast7d) / 7.0).rounded())
        if dailyAverage > Thresholds.heavyDailyAverageMinutes {
            flags.append(Flag(
                flagType: .heavyUsage,
                appIdentifier: metrics.appIdentifier,
                severity: .info,
                message: "\(appName) averaged \(dailyAverage) minutes per day last week."
            ))
        }

        return flags
    }

    /// Ports `analyzeAll`: per-app evaluation plus the streak-reward flag.
    public static func evaluateAll(
        metrics: [Metrics],
        currentStreak: Int,
        hasRecentStreakReward: Bool,
        now: Date = Date(),
        friendlyName: (String) -> String = { $0 }
    ) -> [Flag] {
        var flags = metrics.flatMap { evaluate($0, friendlyName: friendlyName) }

        if currentStreak >= Thresholds.streakRewardDays && !hasRecentStreakReward {
            flags.append(Flag(
                flagType: .streakReward,
                severity: .info,
                message: "7-day proof streak. The trusted contact can consider this positive context during reviews.",
                createdAt: now
            ))
        }

        return flags
    }
}

/// Supplies the metrics `BehaviorRules` evaluates.
///
/// The iOS implementation is expected to be backed by a `DeviceActivityReport`
/// extension (Apple's only supported usage feed) and therefore **cannot** run in
/// the app process or on Linux. This protocol exists so the rules stay testable
/// and so the future adapter has a defined seam.
public protocol BehaviorMetricsProvider: Sendable {
    /// Metrics for the tracked apps over the provider's own window.
    func metrics() async -> [BehaviorRules.Metrics]

    /// Whether the platform can actually supply metrics right now (e.g.
    /// Screen Time authorization granted *and* a report extension installed).
    var isAvailable: Bool { get }
}

/// Persists raised behaviour-rule flags (`RuleFlag` table on Android).
public protocol BehaviorRuleRepository: Sendable {
    func save(_ flags: [BehaviorRules.Flag]) async
    func load() async -> [BehaviorRules.Flag]
    func count(of type: BehaviorRules.FlagType, since date: Date) async -> Int
}

/// In-memory repository used by tests and previews.
public actor InMemoryBehaviorRuleRepository: BehaviorRuleRepository {
    private var flags: [BehaviorRules.Flag] = []

    public init(seed: [BehaviorRules.Flag] = []) {
        self.flags = seed
    }

    public func save(_ flags: [BehaviorRules.Flag]) async {
        self.flags.append(contentsOf: flags)
    }

    public func load() async -> [BehaviorRules.Flag] { flags }

    public func count(of type: BehaviorRules.FlagType, since date: Date) async -> Int {
        flags.filter { $0.flagType == type && $0.createdAt >= date }.count
    }
}

/// Metrics provider that always reports unavailability — the honest default on
/// platforms without a report extension. It never fabricates usage data.
public struct UnavailableBehaviorMetricsProvider: BehaviorMetricsProvider {
    public init() {}
    public var isAvailable: Bool { false }
    public func metrics() async -> [BehaviorRules.Metrics] { [] }
}

/// Orchestrates a single evaluation pass: pull metrics (if available), apply the
/// rules, persist the flags, and return them. Ports Android's `analyzeAll`
/// wiring without pretending to observe usage the platform does not expose.
public struct BehaviorRuleEvaluation: Sendable {
    private let provider: BehaviorMetricsProvider
    private let repository: BehaviorRuleRepository

    public init(provider: BehaviorMetricsProvider, repository: BehaviorRuleRepository) {
        self.provider = provider
        self.repository = repository
    }

    /// Whether the platform can actually supply metrics right now.
    public var isAvailable: Bool { provider.isAvailable }

    /// Runs one pass. When the provider is unavailable the result is empty and
    /// nothing is persisted — never fabricated.
    @discardableResult
    public func run(currentStreak: Int, hasRecentStreakReward: Bool, now: Date = Date()) async -> [BehaviorRules.Flag] {
        guard provider.isAvailable else { return [] }
        let metrics = await provider.metrics()
        let flags = BehaviorRules.evaluateAll(
            metrics: metrics,
            currentStreak: currentStreak,
            hasRecentStreakReward: hasRecentStreakReward,
            now: now
        )
        if !flags.isEmpty {
            await repository.save(flags)
        }
        return flags
    }
}
