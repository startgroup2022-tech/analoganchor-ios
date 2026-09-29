import Foundation

/// The weekly points economy ("Reserve Ledger") for Analog Anchor.
///
/// Ported from the ledger logic in `AnchorViewModel.kt`:
///   - `addPoints` / `deductPoints`
///   - `checkWeeklyFridayReset` (Friday-morning clean slate)
///   - weekly 500-point ceiling + banked stake carry-over
///
/// The ledger is intentionally value-type and deterministic: given a starting
/// state and a sequence of transactions it produces the same balance the Android
/// app would. Persistence is handled by the Storage layer.
public enum Ledger {

    // MARK: - Constants

    /// Weekly ceiling documented in the specification.
    ///
    /// AF-1 note: the Android `AnchorViewModel` never clamps `reserve_points`
    /// (it only floors it at 0), but the ceiling is an explicit product rule
    /// stated in three shipped specification documents, all describing the same
    /// intent ("Weekly ledger caps at 500 PTS", "Max Ceiling: 500 PTS", "500 PTS
    /// weekly ceiling"):
    ///   - `Analog_Anchor_Main_iOS_System_Specification.docx` (Pillar 6)
    ///   - `Outdoor_Tab_Master_Specification.docx` (Weekly Accountability Ledger)
    ///   - `analog_anchor_architecture_and_philosophy.csv` (Weekly Points Economy)
    /// The rule's stated purpose is to prevent point hoarding. The ceiling is
    /// therefore kept as the intended domain behaviour rather than matching the
    /// Android implementation's omission. Android is left untouched.
    public static let weeklyCeiling = 500

    /// The weekday (Calendar weekday value) on which the ledger resets.
    /// 6 == Friday in `Calendar`'s 1...7 = Sunday...Saturday convention.
    public static let resetWeekday = 6

    // MARK: - Types

    public enum TransactionType: String, Codable, Sendable {
        case earn
        case penalty
    }

    public struct Transaction: Identifiable, Equatable, Codable, Sendable {
        public let id: UUID
        public let date: Date
        public let points: Int
        public let reason: String
        public let category: String
        public let type: TransactionType

        public init(
            id: UUID = UUID(),
            date: Date,
            points: Int,
            reason: String,
            category: String,
            type: TransactionType
        ) {
            self.id = id
            self.date = date
            self.points = points
            self.reason = reason
            self.category = category
            self.type = type
        }
    }

    /// Aggregate ledger state for the current week.
    public struct State: Equatable, Sendable {
        /// Spendable reserve built this week (caps at `weeklyCeiling`).
        public var reservePoints: Int
        /// Points carried over from previous weeks (never negative).
        public var bankedStakePoints: Int
        /// Date of the last Friday reset (nil if never reset).
        public var lastResetDate: Date?
        public var transactions: [Transaction]

        public init(
            reservePoints: Int = 0,
            bankedStakePoints: Int = 0,
            lastResetDate: Date? = nil,
            transactions: [Transaction] = []
        ) {
            self.reservePoints = reservePoints
            self.bankedStakePoints = bankedStakePoints
            self.lastResetDate = lastResetDate
            self.transactions = transactions
        }

        /// Progress towards the weekly ceiling (0...1).
        public var weeklyProgress: Double {
            guard Ledger.weeklyCeiling > 0 else { return 0 }
            return min(1.0, max(0.0, Double(reservePoints) / Double(Ledger.weeklyCeiling)))
        }

        /// True once the 150-point (30%) Day Guard unlock milestone is reached.
        public var dayGuardUnlockMilestoneReached: Bool {
            reservePoints >= 150
        }
    }

    // MARK: - Mutations

    /// Applies a positive or negative transaction, clamping the reserve to
    /// 0...`weeklyCeiling`, matching Android's clamp behaviour.
    public static func apply(
        _ transaction: Transaction,
        to state: inout State
    ) {
        let delta = transaction.points
        state.reservePoints = min(weeklyCeiling, max(0, state.reservePoints + delta))
        state.transactions.append(transaction)
    }

    public static func earn(
        _ points: Int,
        reason: String,
        category: String,
        at date: Date = Date(),
        state: inout State
    ) {
        apply(
            Transaction(date: date, points: abs(points), reason: reason, category: category, type: .earn),
            to: &state
        )
    }

    public static func deduct(
        _ points: Int,
        reason: String,
        category: String,
        at date: Date = Date(),
        state: inout State
    ) {
        apply(
            Transaction(date: date, points: -abs(points), reason: reason, category: category, type: .penalty),
            to: &state
        )
    }

    // MARK: - Weekly reset

    /// Returns true when the Friday-morning reset should run for `date`.
    public static func shouldReset(on date: Date, state: State, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.weekday, from: date) == resetWeekday else { return false }
        let todayKey = dayKey(date, calendar: calendar)
        let lastKey = state.lastResetDate.map { dayKey($0, calendar: calendar) }
        return lastKey != todayKey
    }

    /// Performs the Friday clean slate: banks the accumulated reserve, zeroes the
    /// weekly balance and records the reset. Streak resets are handled by
    /// `Streaks.resetWeekly`.
    @discardableResult
    public static func performWeeklyReset(
        for date: Date,
        state: inout State,
        calendar: Calendar = .current
    ) -> Bool {
        guard shouldReset(on: date, state: state, calendar: calendar) else { return false }
        state.bankedStakePoints += max(0, state.reservePoints)
        state.reservePoints = 0
        state.lastResetDate = date
        state.transactions.append(
            Transaction(
                date: date,
                points: 0,
                reason: "Weekly Reserve Reset (Friday Morning)",
                category: "reset",
                type: .penalty
            )
        )
        return true
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
