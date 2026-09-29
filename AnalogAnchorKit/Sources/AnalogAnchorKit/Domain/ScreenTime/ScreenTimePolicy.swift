import Foundation

/// Portable, Codable description of a Screen Time policy.
///
/// Deliberately free of any Apple framework types: the app maps this to
/// `DeviceActivitySchedule` / `ManagedSettingsStore`, the extensions read it
/// back from the App Group, and unit tests exercise it on Linux.
///
/// A policy is a set of **rules**. Each rule has:
/// - an optional daily time budget (minutes), enforced via `DeviceActivityEvent`
///   thresholds, and/or
/// - an optional time window (bedtime / wind-down), enforced via
///   `DeviceActivitySchedule`.
///
/// Enforcement (shields) is applied by the app / extensions from the *current*
/// policy state computed here; this type never touches ManagedSettings itself.
public struct ScreenTimePolicy: Codable, Equatable, Sendable {

    public enum Weekday: Int, Codable, CaseIterable, Sendable {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

        public var shortName: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }
    }

    public struct Rule: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            /// A strict daily ceiling on total usage of the shielded selection.
            case dailyLimit
            /// A continuous blocked window (bedtime, wind-down, Fajr lockdown).
            case window
        }

        public var id: UUID
        public var kind: Kind
        public var name: String

        /// Daily budget in minutes. Nil for `.window` rules.
        public var dailyLimitMinutes: Int?

        /// Window bounds in minutes from midnight. Nil for `.dailyLimit` rules.
        public var startMinutes: Int?
        public var endMinutes: Int?

        /// Days the rule applies to. Empty means "every day".
        public var weekdays: Set<Weekday>

        public var isEnabled: Bool

        public init(
            id: UUID = UUID(),
            kind: Kind,
            name: String,
            dailyLimitMinutes: Int? = nil,
            startMinutes: Int? = nil,
            endMinutes: Int? = nil,
            weekdays: Set<Weekday> = [],
            isEnabled: Bool = true
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.dailyLimitMinutes = dailyLimitMinutes
            self.startMinutes = startMinutes
            self.endMinutes = endMinutes
            self.weekdays = weekdays
            self.isEnabled = isEnabled
        }

        /// Window crossing midnight (bedtime 22:00 → 07:00).
        public var crossesMidnight: Bool {
            guard let s = startMinutes, let e = endMinutes else { return false }
            return e <= s
        }
    }

    public var isEnabled: Bool
    public var rules: [Rule]
    /// Last time the policy was edited (used for the 17:00 edit lock).
    ///
    /// Persisted at whole-second granularity (see `SharedPolicyStore`), so this
    /// is truncated on creation to keep in-memory and reloaded values `Equatable`.
    public var updatedAt: Date

    public init(isEnabled: Bool = false, rules: [Rule] = [], updatedAt: Date = Date()) {
        self.isEnabled = isEnabled
        self.rules = rules
        self.updatedAt = Date(timeIntervalSince1970: updatedAt.timeIntervalSince1970.rounded(.down))
    }

    // MARK: - Derived

    public var activeRules: [Rule] { rules.filter(\.isEnabled) }

    public var dailyLimitRules: [Rule] { activeRules.filter { $0.kind == .dailyLimit } }

    public var windowRules: [Rule] { activeRules.filter { $0.kind == .window } }

    /// The effective daily budget: the strictest (smallest) configured limit,
    /// falling back to the default ceiling.
    public var effectiveDailyLimitMinutes: Int {
        let configured = dailyLimitRules.compactMap(\.dailyLimitMinutes).filter { $0 > 0 }
        return configured.min() ?? AnalogAnchorConfig.defaultProtectedAppDailyLimitMinutes
    }

    // MARK: - Windows

    /// Whether any enabled window rule covers `date`'s wall-clock time.
    public func isBlockedByWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        firstOpenWindow(at: date, calendar: calendar) != nil
    }

    /// The first enabled window rule that is open at `date`, if any.
    ///
    /// Used to decide the *initial* shield state when the engine is switched on:
    /// the engine enforces windows and thresholds, so it must not shield while
    /// no window is open and no limit has been reached.
    public func firstOpenWindow(at date: Date, calendar: Calendar = .current) -> Rule? {
        for rule in windowRules {
            guard let s = rule.startMinutes, let e = rule.endMinutes else { continue }
            if !rule.weekdays.isEmpty {
                guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else { continue }
                // For a midnight-crossing window the *previous* day determines
                // whether the early-morning tail applies.
                let effectiveDay: Weekday
                if e <= s {
                    let hour = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
                    effectiveDay = hour < e ? previousWeekday(weekday) : weekday
                } else {
                    effectiveDay = weekday
                }
                if !rule.weekdays.contains(effectiveDay) { continue }
            }
            let window = Policies.TimeWindow(startMinutes: s, endMinutes: e)
            if window.contains(date, calendar: calendar) { return rule }
        }
        return nil
    }

    private func previousWeekday(_ day: Weekday) -> Weekday {
        let raw = day.rawValue - 1
        return Weekday(rawValue: raw < 1 ? 7 : raw) ?? .saturday
    }

    // MARK: - Validation

    public enum ValidationError: Error, Equatable {
        case dailyLimitOutOfRange(Int)
        case windowStartOutOfRange(Int)
        case windowEndOutOfRange(Int)
        case windowMissingBounds
        case emptySelection
    }

    /// Validates a candidate rule before it is persisted.
    public static func validate(_ rule: Rule) throws {
        switch rule.kind {
        case .dailyLimit:
            let minutes = rule.dailyLimitMinutes ?? 0
            guard minutes > 0, minutes <= 24 * 60 else {
                throw ValidationError.dailyLimitOutOfRange(minutes)
            }
        case .window:
            guard let s = rule.startMinutes, let e = rule.endMinutes else {
                throw ValidationError.windowMissingBounds
            }
            guard (0..<24 * 60).contains(s) else { throw ValidationError.windowStartOutOfRange(s) }
            guard (0..<24 * 60).contains(e) else { throw ValidationError.windowEndOutOfRange(e) }
        }
    }

    public static func validate(_ policy: ScreenTimePolicy) throws {
        for rule in policy.rules { try validate(rule) }
    }
}
