import Foundation

/// Pure, testable scheduling policies ported from the Android baseline.
///
/// These are *outcome* definitions only. Phase 2 deliberately does NOT enforce
/// them (no FamilyControls / ManagedSettings / DeviceActivity). Phase 3 will map
/// these windows onto Screen Time schedules and shields.
public enum Policies {

    /// Tempoary lens for Soft Landing which applies to Dhuhr/Asr/Maghrib only.
    /// Isha was explicitly purged from the buffer scheduler on Android.
    public static let softLandingPrayers: Set<String> = ["dhuhr", "asr", "maghrib"]

    /// Time-of-day window expressed in minutes from midnight, inclusive of the
    /// start and exclusive of the end. Windows may cross midnight when
    /// `endMinutes <= startMinutes` (e.g. bedtime 22:00 -> 07:00).
    public struct TimeWindow: Equatable, Sendable {
        public let startMinutes: Int
        public let endMinutes: Int

        public init(startMinutes: Int, endMinutes: Int) {
            self.startMinutes = startMinutes
            self.endMinutes = endMinutes
        }

        public init?(start: String, end: String) {
            guard let s = Policies.minutes(from: start),
                  let e = Policies.minutes(from: end) else { return nil }
            self.startMinutes = s
            self.endMinutes = e
        }

        /// Whether `date`'s wall-clock time falls inside this window.
        public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
            let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            if startMinutes <= endMinutes {
                return minutes >= startMinutes && minutes < endMinutes
            }
            // Crosses midnight.
            return minutes >= startMinutes || minutes < endMinutes
        }

        /// Whether this is a bedtime-style window that crosses midnight.
        public var crossesMidnight: Bool { endMinutes <= startMinutes }
    }

    /// The daily strict ceiling applied to a protected app (minutes).
    public static func effectiveDailyLimit(_ configured: Int?) -> Int {
        guard let configured, configured > 0 else {
            return AnalogAnchorConfig.defaultProtectedAppDailyLimitMinutes
        }
        return configured
    }

    /// Duration buttons are clamped to the remaining daily quota; the largest
    /// offered value never exceeds the remaining minutes (Radical Scarcity).
    public static func availableDurations(remainingMinutes: Int, requested: [Int] = [2, 5, 10, 30]) -> [Int] {
        let remaining = max(0, remainingMinutes)
        var result = requested.filter { $0 <= remaining }
        if result.isEmpty && remaining > 0 {
            result = [remaining]
        }
        if let maxRequested = requested.max(), remaining > maxRequested, !result.contains(maxRequested) {
            result.append(maxRequested)
        }
        return result.sorted()
    }

    /// Whether policy edits are still allowed today.
    /// Android locked bedtime/accountability edits every day at 17:00 and kept
    /// them immutable until sunrise. Kept as a pure predicate for reuse.
    public static func isPolicyEditWindowOpen(now: Date, calendar: Calendar = .current, lockdownMinutes: Int = 17 * 60) -> Bool {
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return minutes < lockdownMinutes
    }

    // MARK: - Parsing

    /// Parses "HH:mm" into minutes from midnight.
    public static func minutes(from hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        return h * 60 + m
    }
}
