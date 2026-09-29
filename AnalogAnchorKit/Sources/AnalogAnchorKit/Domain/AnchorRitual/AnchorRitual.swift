import Foundation

/// "Thinking on Paper" focus-session domain, ported from the session logic in
/// `AnchorViewModel.kt` (`startFocusSession`, `completeFocusSession`,
/// `isDurationAvailable`, `handleFocusOrientation`/`recordFocusPickup`).
///
/// This is a pure state machine. The stores it needs (ledger, streaks) are
/// applied by the caller, so nothing here touches persistence, sensors or UI.
///
/// Android's `ANCHOR_TAP_ONE_TEST_MODE` (a 15-second debug override) is *not*
/// ported: it is a development flag, not business logic.
public enum AnchorRitual {

    /// Offered session lengths (minutes), exactly the Android anchor options
    /// (`Triple(5, "Short", …)`, `10`, `15`). Default selection is 5.
    public static let offeredDurations = [5, 10, 15]

    /// `FOCUS_PICKUP_LIMIT` — surfaced in the session summary, does not void.
    public static let pickupLimit = 3

    /// `PICKUP_DEBOUNCE_MS` — ignore repeat lift events within this window.
    public static let pickupDebounce: TimeInterval = 1.5

    /// Points awarded on completion, keyed by duration (`earnedPoints`).
    public static func earnedPoints(forDurationMinutes minutes: Int) -> Int {
        switch minutes {
        case 10: return 35
        case 15: return 45
        default: return 25
        }
    }

    /// Daily caps that gate which durations are offered (`isDurationAvailable`).
    public struct DailyCounters: Equatable, Sendable {
        /// `daily_25m_count_<date>` — number of short (5-minute) sessions today.
        public var shortSessionCount: Int
        /// `daily_long_session_<date>` — whether a >5-minute session ran today.
        public var hasLongSessionToday: Bool
        /// `daily_reflection_count_<date>` — completed-session counter, independent
        /// of the duration split.
        public var reflectionCount: Int

        public init(shortSessionCount: Int = 0, hasLongSessionToday: Bool = false, reflectionCount: Int = 0) {
            self.shortSessionCount = shortSessionCount
            self.hasLongSessionToday = hasLongSessionToday
            self.reflectionCount = reflectionCount
        }

        /// Ports `isDurationAvailable`. A long session already used exhausts the
        /// day; otherwise at most two 5-minute sessions, and long durations only
        /// while no short session has run.
        public func isDurationAvailable(_ minutes: Int) -> Bool {
            if hasLongSessionToday { return false }
            return minutes == 5 ? shortSessionCount < 2 : shortSessionCount == 0
        }
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case running
        case completed
        case cancelled
    }

    public struct State: Equatable, Sendable {
        public var phase: Phase
        /// Configured length of the current session, in minutes.
        public var durationMinutes: Int
        /// Seconds remaining on the countdown.
        public var remainingSeconds: Int
        /// Session start, recorded by `start`.
        public var startedAt: Date?
        /// `focusPickupCount` — devices pickups observed during the session.
        public var pickupCount: Int
        /// `focusPhoneFaceDown` — current orientation invariant.
        public var isPhoneFaceDown: Bool
        /// Last accepted pickup timestamp, for debounce.
        public var lastPickupAt: Date?

        public init(
            phase: Phase = .idle,
            durationMinutes: Int = 25,
            remainingSeconds: Int = 0,
            startedAt: Date? = nil,
            pickupCount: Int = 0,
            isPhoneFaceDown: Bool = false,
            lastPickupAt: Date? = nil
        ) {
            self.phase = phase
            self.durationMinutes = durationMinutes
            self.remainingSeconds = remainingSeconds
            self.startedAt = startedAt
            self.pickupCount = pickupCount
            self.isPhoneFaceDown = isPhoneFaceDown
            self.lastPickupAt = lastPickupAt
        }

        public var isActive: Bool { phase == .running }
    }

    /// Result of completing a session — what the caller must credit.
    public struct Completion: Equatable, Sendable {
        public var durationMinutes: Int
        public var points: Int
        public var pickupCount: Int
        /// `evening_anchor_completed_<date>` — the "fully capped" flag.
        public var eveningAnchorCompleted: Bool
        public var reflectionCount: Int
        public var shortSessionCount: Int
        public var hasLongSessionToday: Bool
    }

    public enum RitualError: Error, Equatable {
        case durationUnavailable(Int)
        case notRunning
    }

    // MARK: - Transitions

    /// Ports the start of `startFocusSession`. Countdown begins at the full
    /// duration and discipline state is reset. Returns the fresh state.
    public static func start(
        durationMinutes: Int,
        counters: DailyCounters,
        now: Date = Date()
    ) throws -> State {
        guard counters.isDurationAvailable(durationMinutes) else {
            throw RitualError.durationUnavailable(durationMinutes)
        }
        return State(
            phase: .running,
            durationMinutes: durationMinutes,
            remainingSeconds: max(0, durationMinutes * 60),
            startedAt: now,
            pickupCount: 0,
            isPhoneFaceDown: false,
            lastPickupAt: nil
        )
    }

    /// Advances the countdown; caller drives this from a timer. Returns the
    /// state with updated `remainingSeconds` (clamped at 0). Phase is unchanged;
    /// completion is an explicit decision (`complete`).
    public static func tick(_ state: inout State, elapsedSeconds: Int) {
        guard state.phase == .running else { return }
        state.remainingSeconds = max(0, state.remainingSeconds - max(0, elapsedSeconds))
    }

    /// Ports the completion branch of `completeFocusSession`: computes the new
    /// daily counters and the points to credit.
    public static func complete(_ state: inout State, counters: DailyCounters) throws -> Completion {
        guard state.phase == .running else { throw RitualError.notRunning }
        let duration = state.durationMinutes
        let newShortCount = counters.shortSessionCount + (duration == 5 ? 1 : 0)
        let newLongSession = counters.hasLongSessionToday || duration > 5
        let isFullyCapped = newLongSession || (newShortCount >= 2)

        state.phase = .completed
        state.remainingSeconds = 0

        return Completion(
            durationMinutes: duration,
            points: earnedPoints(forDurationMinutes: duration),
            pickupCount: state.pickupCount,
            eveningAnchorCompleted: isFullyCapped,
            reflectionCount: counters.reflectionCount + 1,
            shortSessionCount: newShortCount,
            hasLongSessionToday: newLongSession
        )
    }

    /// Ports the cancel path: Android clears the session without crediting
    /// points. Pickups were only ever informational, so nothing is deducted here.
    public static func cancel(_ state: inout State) {
        guard state.phase == .running else { return }
        state.phase = .cancelled
        state.remainingSeconds = 0
    }

    /// Ports `recordFocusPickup` + `PICKUP_DEBOUNCE_MS`: a lift after the debounce
    /// increments the count. Motion pickups never void a session.
    public static func recordPickup(_ state: inout State, at now: Date = Date()) {
        guard state.phase == .running else { return }
        if let last = state.lastPickupAt, now.timeIntervalSince(last) < pickupDebounce { return }
        state.pickupCount += 1
        state.lastPickupAt = now
    }

    /// Ports the orientation rule in `handleFocusOrientation`.
    ///
    /// Android reads the accelerometer directly; iOS feeds the already-derived
    /// face-down decision (device resting flat, screen down) from a motion
    /// adapter. Face-down arms the invariant; the next lift can count a pickup.
    public static func updateOrientation(_ state: inout State, isFaceDown: Bool, at now: Date = Date()) {
        guard state.phase == .running else { return }
        let wasFaceDown = state.isPhoneFaceDown
        state.isPhoneFaceDown = isFaceDown
        if wasFaceDown && !isFaceDown {
            recordPickup(&state, at: now)
        }
    }
}
