import Foundation

/// Fajr / Jumu'ah / nightly-discipline domain, ported from `AnchorViewModel.kt`.
///
/// Pure timing and state rules only. Alarm playback, step sensors and NFC live
/// behind adapters (`StepCountingProviding`, `NFCProviding`) and are supplied as
/// booleans/values here, so this type runs on Linux and never touches AlarmKit,
/// `UNUserNotificationCenter`, CoreMotion or CoreNFC.
public enum FajrDomain {

    /// `FAJR_WAKE_STEP_GOAL` — steps needed after dismissal to prove the wake.
    public static let wakeStepGoal = 2

    /// `fajr_alarm_offset_minutes` default (lead relative to Adhan).
    public static let defaultOffsetMinutes = 0

    /// The three accepted Fajr proofs (`fajr_verified`, `fajr_wake_verified`,
    /// `prayer_verified_fajr`), minus the explicit miss flag.
    public struct DailyProofs: Equatable, Sendable {
        public var alarmDismissedInApp: Bool
        public var wakeStepVerified: Bool
        public var prayerVerified: Bool
        public var missed: Bool

        public init(
            alarmDismissedInApp: Bool = false,
            wakeStepVerified: Bool = false,
            prayerVerified: Bool = false,
            missed: Bool = false
        ) {
            self.alarmDismissedInApp = alarmDismissedInApp
            self.wakeStepVerified = wakeStepVerified
            self.prayerVerified = prayerVerified
            self.missed = missed
        }

        /// Ports `recalculateTodayPrayerStatus`'s Fajr clause and the same test
        /// used by `recalculateCovenantStats`.
        public var isFajrSatisfied: Bool {
            guard !missed else { return false }
            return alarmDismissedInApp || wakeStepVerified || prayerVerified
        }
    }

    /// Sleep-pressure status derived from the time until the next Fajr
    /// (`_sleepPressureStatus`).
    public enum SleepPressure: String, Equatable, Sendable {
        case normal = "NORMAL"
        case nightWindow = "NIGHT_WINDOW"
        case lastWindow = "LAST_WINDOW"
        case minimum = "MINIMUM"
    }

    /// Ports the `_sleepPressureStatus` computation.
    ///
    /// `NORMAL` outside the night window (after Isha or before Fajr). Inside it,
    /// the thresholds are strict `<=`: 5h → MINIMUM, 6h → LAST_WINDOW, else the
    /// open NIGHT_WINDOW.
    public static func sleepPressure(timeUntilFajr: TimeInterval, isNightWindow: Bool) -> SleepPressure {
        guard isNightWindow else { return .normal }
        if timeUntilFajr <= 5 * 3600 { return .minimum }
        if timeUntilFajr <= 6 * 3600 { return .lastWindow }
        return .nightWindow
    }

    /// Whether the current instant is in the night discipline window: after
    /// today's Isha or before today's Fajr.
    public static func isNightDisciplineWindow(now: Date, fajr: Date, isha: Date) -> Bool {
        now > isha || now < fajr
    }

    /// The Fajr prayer window: Fajr until sunrise + 30 minutes
    /// (`isFajrWindowActive`).
    public static func isFajrWindowActive(now: Date, fajr: Date, sunrise: Date) -> Bool {
        let end = sunrise.addingTimeInterval(30 * 60)
        return now >= fajr && now <= end
    }

    /// The Maghrib-to-Isha retreat window: 15 minutes before Maghrib until
    /// 60 minutes after Isha (`isMaghribRetreatWindowActive`).
    public static func isMaghribRetreatWindowActive(now: Date, maghrib: Date, isha: Date) -> Bool {
        let start = maghrib.addingTimeInterval(-15 * 60)
        let end = isha.addingTimeInterval(60 * 60)
        return now >= start && now <= end
    }

    /// Friday-clearing rule from `dismissFajrAlarm`: a 7-day NFC repeat expires
    /// at the stored deadline, which also disables the alarm.
    public static func hasRepeatExpired(now: Date, repeatUntil: Date?) -> Bool {
        guard let repeatUntil else { return false }
        return now >= repeatUntil
    }

    /// Jumu'ah miss rule (`checkFridayJumuahMissedAt3PM`): only relevant on
    /// Friday, and only after 14:00 local time.
    public static func isJumuahMissCheckDue(now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.weekday, from: now) == 6 else { return false }
        return calendar.component(.hour, from: now) >= 14
    }

    /// Tracks the post-dismissal wake-step proof (`startFajrWakeStepVerification`,
    /// `updateFajrWakeStepVerification`). Steps accumulate from a baseline and
    /// clamp at `wakeStepGoal`; reaching the goal proves the wake.
    public struct WakeStepTracker: Equatable, Sendable {
        /// Baseline counter value captured when verification armed; `nil` until
        /// the first sample (Android used -1f).
        public var baseline: Int?
        public var stepsAfterDismiss: Int
        public var isActive: Bool

        public init(baseline: Int? = nil, stepsAfterDismiss: Int = 0, isActive: Bool = false) {
            self.baseline = baseline
            self.stepsAfterDismiss = stepsAfterDismiss
            self.isActive = isActive
        }

        public mutating func arm(baseline: Int?) {
            self.baseline = baseline
            self.stepsAfterDismiss = 0
            self.isActive = true
        }

        /// Feeds a cumulative step-counter value. Returns `true` the moment the
        /// goal is reached (the caller marks the wake proof).
        public mutating func update(cumulativeSteps: Int) -> Bool {
            guard isActive else { return false }
            guard let baseline else {
                self.baseline = cumulativeSteps
                return false
            }
            let walked = min(wakeStepGoal, max(stepsAfterDismiss, cumulativeSteps - baseline))
            stepsAfterDismiss = max(0, walked)
            if stepsAfterDismiss >= wakeStepGoal {
                isActive = false
                return true
            }
            return false
        }

        /// Feeds a single step-detector event (+1).
        public mutating func recordDetectorStep() -> Bool {
            guard isActive else { return false }
            stepsAfterDismiss = min(wakeStepGoal, stepsAfterDismiss + 1)
            if stepsAfterDismiss >= wakeStepGoal {
                isActive = false
                return true
            }
            return false
        }
    }

    /// The reward credited by `markFajrWakeProof`.
    public static let wakeProofPoints = 10
    public static let wakeProofReason = "Fajr Wake Proof"
}
