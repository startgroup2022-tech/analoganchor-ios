import Foundation

/// Streak tracking for the four behavioural pillars (mirrors Android).
///
/// Android kept separate streaks in SharedPreferences
/// (`protocol_streak`, `maghrib_retreat_streak`, `mosque_streak`,
/// `anchor_streak`) and reset them during `checkWeeklyFridayReset`.
/// This type centralizes that state and the Friday reset.
public enum Streaks {

    public enum Pillar: String, CaseIterable, Codable, Sendable {
        /// Thinking-on-Paper ritual sessions.
        case anchor
        /// Maghrib-to-Isha sacred retreat.
        case maghribRetreat
        /// Verified mosque attendance.
        case mosque
        /// General protocol compliance.
        case protocolCompliance

        public var displayName: String {
            switch self {
            case .anchor: return "PAPER RITUAL"
            case .maghribRetreat: return "RETREAT"
            case .mosque: return "MOSQUE"
            case .protocolCompliance: return "PROTOCOL"
            }
        }
    }

    public struct State: Equatable, Codable, Sendable {
        public var current: [Pillar: Int]
        public var best: [Pillar: Int]
        public var lastStreakUpdate: Date?

        public init(
            current: [Pillar: Int] = [:],
            best: [Pillar: Int] = [:],
            lastStreakUpdate: Date? = nil
        ) {
            self.current = current
            self.best = best
            self.lastStreakUpdate = lastStreakUpdate
        }

        public func current(_ pillar: Pillar) -> Int { current[pillar] ?? 0 }
        public func best(_ pillar: Pillar) -> Int { best[pillar] ?? 0 }
    }

    /// Increments a pillar's streak and tracks the best value.
    public static func increment(_ pillar: Pillar, in state: inout State, at date: Date = Date()) {
        let next = (state.current[pillar] ?? 0) + 1
        state.current[pillar] = next
        state.best[pillar] = max(state.best[pillar] ?? 0, next)
        state.lastStreakUpdate = date
    }

    /// Resets every pillar streak to zero (Friday clean slate).
    public static func resetWeekly(in state: inout State, at date: Date = Date()) {
        for pillar in Pillar.allCases {
            state.current[pillar] = 0
        }
        state.lastStreakUpdate = date
    }

    /// The number of consecutive days ending today for which `isCompleted`
    /// returns true. Walks backwards from `endDate`.
    ///
    /// NOTE: this is a plain unbounded walk. The Android weekly streak
    /// (`calculateConsecutiveStreak`) is week-bounded and allows a grace start
    /// from yesterday — use `weeklyStreak(weekDays:isCompleted:)` for that rule.
    public static func consecutiveDays(
        endingOn endDate: Date,
        calendar: Calendar = .current,
        maxLookback: Int = 400,
        isCompleted: (Date) -> Bool
    ) -> Int {
        var count = 0
        var day = endDate
        for _ in 0..<maxLookback {
            if isCompleted(day) {
                count += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
            } else {
                break
            }
        }
        return count
    }

    /// The Friday-to-today window Android streaks are measured over
    /// (`getDaysInCurrentWeekToToday`). The returned keys are ordered
    /// newest-first: index 0 is today, index 1 yesterday, up to the most recent
    /// Friday. `key` converts a date to the app's date key.
    public static func currentWeekDaysToToday(
        now: Date = Date(),
        calendar: Calendar = .current,
        key: (Date) -> String
    ) -> [String] {
        var cal = calendar
        // Calendar weekday: Sunday=1 … Friday=6, Saturday=7.
        let weekday = cal.component(.weekday, from: now)
        let daysSinceFriday = (weekday - 6 + 7) % 7
        var days: [String] = []
        for offset in 0...daysSinceFriday {
            if let day = cal.date(byAdding: .day, value: -offset, to: now) {
                days.append(key(day))
            }
        }
        return days
    }

    /// Ports `calculateConsecutiveStreak` exactly.
    ///
    /// `weekDays` must be ordered newest-first (today at index 0, as
    /// `getDaysInCurrentWeekToToday` builds it). If today counts, the streak runs
    /// back from today; otherwise, if yesterday counts, it runs back from
    /// yesterday (the grace rule), giving the user the rest of today to keep it.
    public static func weeklyStreak(weekDays: [String], isCompleted: (String) -> Bool) -> Int {
        guard !weekDays.isEmpty else { return 0 }

        func count(from start: Int) -> Int {
            var streak = 0
            for index in start..<weekDays.count {
                if isCompleted(weekDays[index]) { streak += 1 } else { break }
            }
            return streak
        }

        if isCompleted(weekDays[0]) {
            return count(from: 0)
        }
        if weekDays.count > 1 && isCompleted(weekDays[1]) {
            return count(from: 1)
        }
        return 0
    }
}
