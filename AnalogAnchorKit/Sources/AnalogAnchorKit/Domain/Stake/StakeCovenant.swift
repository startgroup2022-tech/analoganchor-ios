import Foundation

/// Stake + Covenant economy, ported from `AnchorViewModel.kt`.
///
/// Two independent accumulators share this file because they are read together
/// on the same dashboard card:
///
/// - **Stake** (`recalculateStakeStats`): a 12-week install-based timeline and
///   cumulative progress towards a 6000-point stake target.
/// - **Covenant** (`recalculateCovenantStats`): a 40-day "Takbir Covenant"
///   window scoring daily mosque prayers, the Fajr wake proof and outdoor
///   sessions, capped at 8000 points.
///
/// Pure value types only — no persistence, no Apple frameworks, no SwiftUI.
public enum Stake {

    /// Number of weeks the stake cycle runs for (`coerceIn(1, 12)`).
    public static let maxWeeks = 12

    /// Cumulative target behind the stake percentage (`6000f`).
    public static let cumulativeTarget = 6000

    public struct State: Equatable, Sendable {
        /// 1-based week number since install.
        public var week: Int
        /// Sum of banked stake plus the current reserve (never negative).
        public var totalCumulativePoints: Int
        /// `totalCumulativePoints / 6000 * 100` — deliberately not clamped,
        /// matching Android (which can exceed 100 as the stake fills).
        public var cumulativePercentage: Double

        public init(week: Int = 1, totalCumulativePoints: Int = 0, cumulativePercentage: Double = 0) {
            self.week = week
            self.totalCumulativePoints = totalCumulativePoints
            self.cumulativePercentage = cumulativePercentage
        }
    }

    /// Ports `recalculateStakeStats`:
    /// ```
    /// diffDays = max(0, (now - installTs) / day)
    /// week     = ((diffDays / 7) + 1).coerceIn(1, 12)
    /// total    = banked + max(0, reserve)
    /// pct      = (total / 6000f) * 100f
    /// ```
    public static func calculate(
        installDate: Date,
        now: Date = Date(),
        bankedStakePoints: Int,
        reservePoints: Int
    ) -> State {
        let diffDays = max(0, Int(now.timeIntervalSince(installDate) / 86_400))
        let week = min(maxWeeks, max(1, (diffDays / 7) + 1))
        let total = bankedStakePoints + max(0, reservePoints)
        let percentage = (Double(total) / Double(cumulativeTarget)) * 100.0
        return State(week: week, totalCumulativePoints: total, cumulativePercentage: percentage)
    }
}

/// The 40-day Takbir Covenant (`عهد الأربعين يوماً`).
public enum Covenant {

    /// `targetDays` in `claimCovenantMilestoneBonus`.
    public static let targetDays = 40

    /// Upper bound on the accumulated score (`coerceIn(0, 8000)`).
    public static let scoreCeiling = 8000

    /// Minimum score required before the milestone bonus can be claimed (`6000`).
    public static let claimScoreThreshold = 6000

    /// Points awarded once, per cycle, by `claimCovenantMilestoneBonus`.
    public static let milestoneBonusPoints = 500

    /// Points per verified mosque prayer (Dhuhr/Asr/Maghrib/Isha).
    public static let prayerPoints = 40

    /// Points per outdoor session credited inside the covenant.
    public static let outdoorPointsPerSession = 15

    /// `mosquePrayerKeys` in `recalculateCovenantStats`. Fajr is handled
    /// separately because it accepts three alternative proofs.
    public static let mosquePrayerKeys: Set<String> = ["dhuhr", "asr", "maghrib", "isha"]

    /// One day of covenant evidence, flattened from the Android preference keys
    /// `prayer_verified_<p>_<date>`, `fajr_verified_<date>`,
    /// `fajr_wake_verified_<date>`, `fajr_alarm_missed_<date>`,
    /// `outdoor_sessions_<date>`.
    public struct DayEvidence: Equatable, Sendable {
        /// Which of `mosquePrayerKeys` were verified that day.
        public var verifiedMosquePrayers: Set<String>
        public var fajrMosqueVerified: Bool
        public var fajrWakeVerified: Bool
        public var fajrPrayerVerified: Bool
        public var fajrMissed: Bool
        public var outdoorSessionCount: Int

        public init(
            verifiedMosquePrayers: Set<String> = [],
            fajrMosqueVerified: Bool = false,
            fajrWakeVerified: Bool = false,
            fajrPrayerVerified: Bool = false,
            fajrMissed: Bool = false,
            outdoorSessionCount: Int = 0
        ) {
            self.verifiedMosquePrayers = verifiedMosquePrayers
            self.fajrMosqueVerified = fajrMosqueVerified
            self.fajrWakeVerified = fajrWakeVerified
            self.fajrPrayerVerified = fajrPrayerVerified
            self.fajrMissed = fajrMissed
            self.outdoorSessionCount = outdoorSessionCount
        }

        /// Score contributed by a single day, exactly as Android sums it.
        var score: Int {
            var value = verifiedMosquePrayers.intersection(Covenant.mosquePrayerKeys).count * Covenant.prayerPoints
            let fajrProven = fajrMosqueVerified || fajrWakeVerified || fajrPrayerVerified
            if fajrProven && !fajrMissed {
                value += Covenant.prayerPoints
            }
            value += max(0, outdoorSessionCount) * Covenant.outdoorPointsPerSession
            return value
        }
    }

    public struct State: Equatable, Sendable {
        /// 1-based day inside the covenant (`coerceIn(1, 40)`).
        public var dayNumber: Int
        /// Accumulated score, capped at `scoreCeiling`.
        public var score: Int
        /// Integer percentage of `scoreCeiling` (`0...100`).
        public var percentage: Int
        /// Whether this cycle's bonus has already been claimed.
        public var bonusClaimed: Bool

        public init(dayNumber: Int = 1, score: Int = 0, percentage: Int = 0, bonusClaimed: Bool = false) {
            self.dayNumber = dayNumber
            self.score = score
            self.percentage = percentage
            self.bonusClaimed = bonusClaimed
        }

        /// `claimCovenantMilestoneBonus` gate: day 40 reached and score >= 6000.
        public var canClaimMilestoneBonus: Bool {
            dayNumber >= Covenant.targetDays && score >= Covenant.claimScoreThreshold
        }
    }

    /// Ports `recalculateCovenantStats`.
    ///
    /// - Parameter evidence: one entry per elapsed covenant day, index 0 being
    ///   the start day. Android walks `1..currentDay` advancing one calendar day
    ///   at a time; extra entries beyond `currentDay` are ignored.
    public static func calculate(
        startDate: Date,
        now: Date = Date(),
        evidence: [DayEvidence],
        bonusClaimed: Bool = false
    ) -> State {
        let diffDays = Int(now.timeIntervalSince(startDate) / 86_400)
        let dayNumber = min(targetDays, max(1, diffDays + 1))

        var total = 0
        for index in 0..<dayNumber where index < evidence.count {
            total += evidence[index].score
        }

        let capped = min(scoreCeiling, max(0, total))
        let percentage = min(100, max(0, Int((Double(capped) / Double(scoreCeiling)) * 100.0)))
        return State(dayNumber: dayNumber, score: capped, percentage: percentage, bonusClaimed: bonusClaimed)
    }

    /// Ports `claimCovenantMilestoneBonus`'s decision. Returns the ledger points
    /// to award, or `nil` when the claim is not allowed (already claimed, or the
    /// day/score gate is unmet).
    public static func claimMilestoneBonus(state: State) -> Int? {
        guard !state.bonusClaimed else { return nil }
        guard state.canClaimMilestoneBonus else { return nil }
        return milestoneBonusPoints
    }
}
