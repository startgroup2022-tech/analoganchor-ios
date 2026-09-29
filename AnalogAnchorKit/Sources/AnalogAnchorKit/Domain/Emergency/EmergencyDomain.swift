import Foundation

/// Emergency-unlock domain, ported from `AnchorViewModel.kt`.
///
/// Models the state machine Android drives (`LOCKED` ŌåÆ `COOLING` ŌåÆ
/// `READY_TO_REQUEST` ŌåÆ `REQUESTED` ŌåÆ `ACTIVE_UNLOCKED` ŌåÆ `RE_ENTRY`) and the
/// token-freshness rule. It is pure: the actual shield clearing is applied by
/// the caller through the Screen Time adapter, never here.
public enum EmergencyDomain {

    /// `COOLDOWN_DURATION_SEC` — the user-facing cooling window.
    ///
    /// Android's constant carries a `TEST_MODE_COOLDOWN` debug flag (10s in test,
    /// 1500s = 25 min otherwise) while its own state comment documents the rule
    /// as a "60-min countdown in seconds (3600s)". The iOS Protocol screen has
    /// shipped the 60-minute rule since Phase 2, so the documented user-facing
    /// value is used here; the debug flag is not ported.
    public static let cooldownDuration: TimeInterval = 60 * 60

    /// `TOKEN_VALIDITY_MS` ŌĆö a token is only valid within 60 minutes of the
    /// unlock request.
    public static let tokenValidity: TimeInterval = 60 * 60

    /// `ACTIVE_UNLOCK_DURATION_SEC` ŌĆö length of an active unlocked window.
    public static let activeUnlockDuration: TimeInterval = 15

    /// `GRACE_DURATION_SEC` ŌĆö re-entry grace before the shield returns.
    public static let graceDuration: TimeInterval = 25

    /// `RE_ENTRY_PIN_CUSTODY_MS` ŌĆö how long the re-entry PIN is held.
    public static let reEntryPinCustody: TimeInterval = 75 * 60

    public enum State: String, Equatable, Sendable {
        case locked = "LOCKED"
        case cooling = "COOLING"
        case readyToRequest = "READY_TO_REQUEST"
        case requested = "REQUESTED"
        case activeUnlocked = "ACTIVE_UNLOCKED"
        case reEntry = "RE_ENTRY"
    }

    /// Ports `isEmergencyTokenFresh`: a request must exist and be within the
    /// validity window.
    public static func isTokenFresh(requestStart: Date?, now: Date = Date()) -> Bool {
        guard let requestStart else { return false }
        return now.timeIntervalSince(requestStart) <= tokenValidity
    }

    /// Ports `startActiveSessionCountdown`: computes the expiry of an unlocked
    /// window opened `now`.
    public static func activeUnlockExpiry(now: Date = Date()) -> Date {
        now.addingTimeInterval(activeUnlockDuration)
    }

    /// Ports the cooling branch of `updateNextPrayerCountdown`: the executor
    /// decides `READY_TO_REQUEST` once the cooldown elapses.
    public static func coolingRemaining(cooldownStart: Date, now: Date = Date()) -> Int {
        max(0, Int((cooldownStart.addingTimeInterval(cooldownDuration)).timeIntervalSince(now)))
    }

    public static func isCooldownComplete(cooldownStart: Date, now: Date = Date()) -> Bool {
        now >= cooldownStart.addingTimeInterval(cooldownDuration)
    }

    /// The ledger effect of a successful token authorization. Android arms a
    /// 15-second unlocked window; it does not deduct points for token use (only
    /// the credit-based bypasses deduct).
    public struct AuthorizationResult: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// A valid token: shield may be suspended for the unlocked window.
            case token
            /// A `-DEC60` decoy: the illusion is armed, but no real access is
            /// authorized. The caller must NOT clear a real shield for this.
            case decoy
            /// Invalid or expired: nothing changes.
            case rejected
        }

        public var kind: Kind
        public var unlockedUntil: Date?

        /// Whether the caller should suspend the shield. Only a real token does.
        public var shouldSuspendShield: Bool { kind == .token }
    }

    /// Classifies a decoded token against the freshness rule. The actual PIN
    /// decode lives in `TokenCodec`; this only decides the emergency effect.
    public static func evaluate(
        decodedSuccessfully: Bool,
        isDecoy: Bool,
        requestStart: Date?,
        now: Date = Date()
    ) -> AuthorizationResult {
        if !decodedSuccessfully { return AuthorizationResult(kind: .rejected, unlockedUntil: nil) }
        if isDecoy { return AuthorizationResult(kind: .decoy, unlockedUntil: nil) }
        guard isTokenFresh(requestStart: requestStart, now: now) else {
            return AuthorizationResult(kind: .rejected, unlockedUntil: nil)
        }
        return AuthorizationResult(kind: .token, unlockedUntil: activeUnlockExpiry(now: now))
    }

    /// Credits-based bypasses (`bypassLockWithCredits` / `requestReserveUnlock`).
    public static let creditBypassCost = 60
    public static let reserveUnlockCost = 380
}

/// The port the emergency flow uses to lift shields. The concrete iOS adapter
/// drives `ManagedSettingsController`; a View must never call ManagedSettings.
@MainActor
public protocol ShieldSuspending: AnyObject {
    /// Suspends shields (emergency/expiry path) without deleting the policy.
    func suspendShields()
    /// Re-applies shields from the stored policy (re-entry / expiry path).
    func restoreShields()
}
