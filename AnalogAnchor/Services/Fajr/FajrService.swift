import Foundation
import AnalogAnchorKit

/// Fajr / wake-proof coordination.
///
/// Bridges the pure `FajrDomain` rules to the platform services that already
/// exist (notifications, CoreMotion step counting, CoreNFC) and to the persisted
/// daily proof state in the App Group. It owns no business rule of its own: the
/// "is Fajr satisfied", "is the window active" and "wake step goal" decisions
/// all come from `FajrDomain`.
///
/// ## Publishing
/// Apple does **not** offer AlarmKit on every deployment target, and a
/// third-party app cannot take over the device the way Android's AlarmManager +
/// foreground service could. Weather the wake alarm with
/// `UNUserNotificationCenter` (the officially supported route); AlarmKit is used
/// only where the target allows it. No background execution is attempted here.
@MainActor
final class FajrService: ObservableObject {

    @Published private(set) var proofs: FajrDomain.DailyProofs
    @Published private(set) var wakeTracker = FajrDomain.WakeStepTracker()
    @Published private(set) var lastWakeEvent: String?

    private let preferences: PreferencesStore
    private weak var motion: MotionService?
    private weak var notifications: NotificationService?

    /// Called when the wake proof is earned, so the app can credit the domain
    /// reward in one place (the ledger lives in `AppEnvironment`).
    var onWakeProofEarned: ((Int, String) -> Void)?

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        self.proofs = Self.loadProofs(from: preferences)
    }

    func attach(motion: MotionService, notifications: NotificationService) {
        self.motion = motion
        self.notifications = notifications
    }

    // MARK: - Daily state

    /// Reloads the day-scoped proof flags, rolling to a fresh day when needed.
    func reloadDailyState(now: Date = Date()) {
        rollIfNeeded(now: now)
        proofs = Self.loadProofs(from: preferences)
    }

    private func rollIfNeeded(now: Date) {
        let key = Self.dayKey(now)
        guard preferences.string(.fajrProofDate) != key else { return }
        preferences.set(key, for: .fajrProofDate)
        preferences.set(false, for: .fajrAlarmDismissedInApp)
        preferences.set(false, for: .fajrWakeVerified)
        preferences.set(false, for: .fajrPrayerVerified)
        preferences.set(false, for: .fajrMissed)
    }

    private static func loadProofs(from preferences: PreferencesStore) -> FajrDomain.DailyProofs {
        FajrDomain.DailyProofs(
            alarmDismissedInApp: preferences.bool(.fajrAlarmDismissedInApp),
            wakeStepVerified: preferences.bool(.fajrWakeVerified),
            prayerVerified: preferences.bool(.fajrPrayerVerified),
            missed: preferences.bool(.fajrMissed)
        )
    }

    // MARK: - Alarm dismissal

    /// Records that the in-app Fajr alarm was dismissed, which arms the 2-step
    /// wake verification (`startFajrWakeStepVerification`).
    func recordAlarmDismissed(now: Date = Date()) {
        rollIfNeeded(now: now)
        preferences.set(true, for: .fajrAlarmDismissedInApp)
        proofs.alarmDismissedInApp = true
        // Arm step verification with a baseline step count, exactly like the
        // Android flow (baseline captured at dismissal, goal reached afterwards).
        motion?.startLiveStepTracking(from: now)
        wakeTracker.arm(baseline: 0)
    }

    /// Feeds a cumulative step count into the wake tracker; credits the wake
    /// proof the moment the goal is met.
    func updateWakeSteps(cumulativeSteps: Int, now: Date = Date()) {
        guard wakeTracker.isActive else { return }
        if wakeTracker.update(cumulativeSteps: cumulativeSteps) {
            completeWakeProof(reason: "step")
        }
    }

    /// NFC wake proof: the Fajr eraser tag confirms the user physically left bed.
    func recordNFCTag(_ tagID: String, now: Date = Date()) {
        guard !tagID.isEmpty else { return }
        completeWakeProof(reason: "nfc")
    }

    private func completeWakeProof(reason: String) {
        guard !proofs.wakeStepVerified else { return }
        proofs.wakeStepVerified = true
        preferences.set(true, for: .fajrWakeVerified)
        lastWakeEvent = reason == "nfc" ? "Wake proof: NFC tag" : "Wake proof: movement"
        motion?.stopLiveStepTracking()
        onWakeProofEarned?(FajrDomain.wakeProofPoints, FajrDomain.wakeProofReason)
    }

    // MARK: - Prayer verification

    /// Marks the Fajr prayer as verified (mosque/presence path).
    func recordPrayerVerified() {
        proofs.prayerVerified = true
        preferences.set(true, for: .fajrPrayerVerified)
    }

    func recordMissed() {
        proofs.missed = true
        preferences.set(true, for: .fajrMissed)
    }

    /// Marks today's Fajr as missed once its window has closed without any proof.
    /// Called when the app becomes active; the window rule comes from
    /// `FajrDomain.isFajrWindowActive` (Fajr → sunrise + 30 min).
    func evaluateMissedIfDue(times: PrayerTimesCalculator.PrayerTimes, now: Date = Date()) {
        rollIfNeeded(now: now)
        guard !proofs.missed else { return }
        let windowActive = FajrDomain.isFajrWindowActive(now: now, fajr: times.fajr, sunrise: times.sunrise)
        if !windowActive && now > times.sunrise.addingTimeInterval(30 * 60) && !isFajrSatisfied {
            recordMissed()
        }
    }

    /// Whether today's Fajr obligation is satisfied, per the domain rule.
    var isFajrSatisfied: Bool { proofs.isFajrSatisfied }

    // MARK: - Scheduling

    /// Schedules the Fajr reminder + wake window using the real prayer times.
    /// Uses `UNUserNotificationCenter` (the supported path); a Time-Sensitive
    /// interruption level is requested but will silently remain `.active` if the
    /// entitlement is absent ŌĆö no Critical Alert is claimed.
    func scheduleFajr(for times: PrayerTimesCalculator.PrayerTimes, isEnglish: Bool) async {
        await notifications?.schedule(
            id: "fajr_alarm",
            title: isEnglish ? "Fajr" : "ž¦┘ä┘üž¼ž▒",
            body: isEnglish
                ? "Time for Fajr. Dismiss here and walk to prove you are awake."
                : "žŁž¦┘å ┘ł┘éž¬ ž¦┘ä┘üž¼ž▒. žŻž▓┘ä ž¦┘äž¬┘åž©┘Ŗ┘ć ┘ć┘åž¦ ┘łž¦┘ģž┤┘É ┘äžźž½ž©ž¦ž¬ ž¦ž│ž¬┘Ŗ┘éž¦žĖ┘ā.",
            at: times.fajr,
            categoryIdentifier: NotificationService.Category.fajrAlarm,
            timeSensitive: true
        )
    }

    func cancelFajr() {
        notifications?.cancel(id: "fajr_alarm")
    }

    // MARK: - Helpers

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
