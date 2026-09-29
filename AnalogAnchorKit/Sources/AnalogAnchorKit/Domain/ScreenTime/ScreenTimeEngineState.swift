import Foundation

/// Cross-process record of *why* a shield is currently applied.
///
/// The app and the monitor extension run in separate processes, so a
/// `DeviceActivitySchedule` ending must not blindly clear a shield that a daily
/// limit put in place. Each process records the reason it last applied a shield
/// here; on `intervalDidEnd` the monitor clears only if the ending window is the
/// most recent cause.
public struct ScreenTimeEngineState: Codable, Equatable, Sendable {

    public enum ShieldCause: Codable, Equatable, Sendable {
        /// Shielding because a blocked window (bedtime / wind-down) is open.
        case window(ruleID: UUID)
        /// Shielding because a daily usage threshold was reached.
        case dailyLimit(ruleID: UUID)

        public var ruleID: UUID {
            switch self {
            case .window(let id): return id
            case .dailyLimit(let id): return id
            }
        }
    }

    /// The most recent reason a shield was applied; `nil` means no shield.
    public var activeCause: ShieldCause?
    public var updatedAt: Date

    public init(activeCause: ShieldCause? = nil, updatedAt: Date = Date()) {
        self.activeCause = activeCause
        self.updatedAt = updatedAt
    }

    public static let idle = ScreenTimeEngineState(activeCause: nil, updatedAt: .distantPast)
}
