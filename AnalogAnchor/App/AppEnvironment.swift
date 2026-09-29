import Foundation
import SwiftUI
import AnalogAnchorKit

/// Root application state for Analog Anchor (iOS).
///
/// This is the Phase-2 foundation: it owns preferences, the in-memory ledger +
/// streak state, the current prayer times and the Screen Time authorization
/// coordinator. It intentionally mirrors the responsibilities of the Android
/// `AnchorViewModel` without any Android-only system logic.
@MainActor
final class AppEnvironment: ObservableObject {

    // MARK: - Dependencies

    let preferences = PreferencesStore()
    let screenTime: ScreenTimeCoordinator
    let screenTimeManager: ScreenTimeManager
    /// Real DeviceActivityReport-backed behavior metrics (nil in previews/tests).
    let behaviorProvider: BehaviorReportProvider?
    /// Persists raised behavior flags in the App Group.
    let behaviorFlagStore: BehaviorFlagStore

    // MARK: - Observable state

    @Published var isOnboarded: Bool
    @Published var isEnglish: Bool
    @Published var ledger: Ledger.State
    @Published var streaks: Streaks.State
    @Published var prayerTimes: PrayerTimesCalculator.PrayerTimes?
    @Published var locationDescription: String
    @Published var screenTimeStatus: ScreenTimeAuthorizationStatus

    /// Emergency-unlock state machine (domain overlay over Screen Time).
    @Published var emergencyState: EmergencyDomain.State = .locked
    @Published var emergencyCoolDownRemaining: Int = 0

    /// Active "Thinking on Paper" session, if any.
    @Published var ritual: AnchorRitual.State = .init()

    /// Partner accountability session, if any.
    @Published var partnerSession: PartnerDomain.Session?
    /// Set when a pending partner session expired, to show the guilt banner.
    @Published var showPartnerCovenantGuiltBanner = false

    /// Last error surfaced to the UI (e.g. App Group unavailable).
    @Published var lastWarning: String?

    private var standardPreferences: PreferencesStore { preferences }

    // MARK: - Init

    init(
        screenTime: ScreenTimeCoordinator = ScreenTimeCoordinator(),
        screenTimeManager: ScreenTimeManager = ScreenTimeManager(),
        behaviorProvider: BehaviorReportProvider? = nil,
        behaviorFlagStore: BehaviorFlagStore = BehaviorFlagStore()
    ) {
        self.screenTime = screenTime
        self.screenTimeManager = screenTimeManager
        self.behaviorProvider = behaviorProvider
        self.behaviorFlagStore = behaviorFlagStore
        self.isOnboarded = preferences.bool(.isOnboarded)
        self.isEnglish = preferences.bool(.isEnglish, default: true)
        self.screenTimeStatus = screenTime.status
        self.locationDescription = preferences.string(.userLocationName) ?? "GPS pending"

        self.ledger = Ledger.State(
            reservePoints: preferences.int(.reservePoints),
            bankedStakePoints: preferences.int(.bankedStakePoints)
        )
        self.streaks = Streaks.State()

        if !SharedStore.isAppGroupAvailable() {
            lastWarning = "App Group '\(AnalogAnchorConfig.appGroupIdentifier)' is not available in this build. Data will stay app-local until the group is configured in the Apple Developer portal."
        }

        recalculatePrayerTimes()
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        isOnboarded = true
        preferences.set(true, for: .isOnboarded)
    }

    func setEnglish(_ value: Bool) {
        isEnglish = value
        preferences.set(value, for: .isEnglish)
    }

    // MARK: - Prayer times

    /// Effective coordinates, falling back to the Bahrain default (mirrors Android).
    var effectiveCoordinates: (lat: Double, lng: Double) {
        let lat = preferences.double(.userLatitude)
        let lng = preferences.double(.userLongitude)
        if abs(lat) > 0.0001 || abs(lng) > 0.0001 {
            return (lat, lng)
        }
        return (LocationCodeParser.bahrainDefaultLat, LocationCodeParser.bahrainDefaultLng)
    }

    func recalculatePrayerTimes(now: Date = Date()) {
        let coords = effectiveCoordinates
        let tzOffset = Double(TimeZone.current.secondsFromGMT(for: now)) / 3600.0
        let calculator = PrayerTimesCalculator(
            latitude: coords.lat,
            longitude: coords.lng,
            timezoneOffset: tzOffset
        )
        prayerTimes = calculator.calculateTimes(for: now)
    }

    func updateLocation(latitude: Double, longitude: Double, description: String?) {
        preferences.set(latitude, for: .userLatitude)
        preferences.set(longitude, for: .userLongitude)
        setLocationDescription(description ?? String(format: "%.4f, %.4f", latitude, longitude))
        recalculatePrayerTimes()
    }

    /// Persists a location description without changing coordinates.
    func setLocationDescription(_ value: String) {
        locationDescription = value
        preferences.set(value, for: .userLocationName)
    }

    // MARK: - Ledger

    func addPoints(_ points: Int, reason: String, category: String) {
        Ledger.earn(points, reason: reason, category: category, state: &ledger)
        persistLedger()
    }

    func deductPoints(_ points: Int, reason: String, category: String) {
        Ledger.deduct(points, reason: reason, category: category, state: &ledger)
        persistLedger()
    }

    /// Runs the Friday clean slate if due, and resets streak pillars.
    func runWeeklyMaintenanceIfNeeded(now: Date = Date()) {
        if Ledger.performWeeklyReset(for: now, state: &ledger) {
            Streaks.resetWeekly(in: &streaks, at: now)
            persistLedger()
        }
    }

    private func persistLedger() {
        preferences.set(ledger.reservePoints, for: .reservePoints)
        preferences.set(ledger.bankedStakePoints, for: .bankedStakePoints)
    }

    // MARK: - Behavior rules (real DeviceActivityReport-backed)

    /// Raised behaviour flags, newest last. Populated only from the real report
    /// extension; empty when no fresh report exists.
    @Published private(set) var behaviorFlags: [BehaviorRules.Flag] = []

    /// The last real report snapshot written by the DeviceActivityReport
    /// extension (nil until the extension has run at least once). Surfaced so the
    /// UI can show honest provenance instead of placeholder numbers.
    @Published private(set) var behaviorSnapshot: BehaviorReportSnapshot?

    /// Re-reads the report snapshot the extension writes to the App Group.
    /// Called after the report scene renders (that render is what runs the
    /// extension) and when Day Guard appears.
    func refreshBehaviorSnapshot() {
        behaviorSnapshot = behaviorProvider?.currentSnapshot()
    }

    /// Runs one evaluation pass against the DeviceActivityReport snapshot. When
    /// the provider reports unavailability (no authorization / no fresh report)
    /// the result is empty and nothing is fabricated.
    ///
    /// The streak pillar is `.anchor` because Android fed this rule from
    /// `anchor_streak` (`DailyRuleEngineRunner`), the Thinking-on-Paper pillar —
    /// not a separate "paper" pillar that does not exist in `Streaks.Pillar`.
    @discardableResult
    func runBehaviorEvaluation(now: Date = Date()) async -> [BehaviorRules.Flag] {
        guard let provider = behaviorProvider else { return [] }
        let evaluation = BehaviorRuleEvaluation(provider: provider, repository: behaviorFlagStore)
        let hasRecentStreakReward = await behaviorFlagStore.count(
            of: .streakReward,
            since: now.addingTimeInterval(-7 * 86_400)
        ) > 0
        let flags = await evaluation.run(
            currentStreak: streaks.current(.anchor),
            hasRecentStreakReward: hasRecentStreakReward,
            now: now
        )
        behaviorFlags = await behaviorFlagStore.load()
        behaviorSnapshot = provider.currentSnapshot()
        return flags
    }

    /// Whether real usage metrics are currently available (authorization +
    /// fresh report snapshot). The Day Guard screen uses this to be honest.
    var isBehaviorMetricsAvailable: Bool { behaviorProvider?.isAvailable ?? false }

    func clearBehaviorFlags() async {
        // Reload from disk after a reset so the UI reflects reality.
        behaviorFlags = await behaviorFlagStore.load()
    }

    // MARK: - Screen Time

    /// Requests Family Controls authorization and reports the real outcome.
    func requestScreenTimeAuthorization() async {
        let outcome = await screenTime.requestAuthorization()
        screenTimeStatus = outcome.status
        preferences.set(screenTimeStatus.rawValue, for: .screenTimeAuthorizationStatus)
        if let error = outcome.error {
            lastWarning = error.errorDescription
        } else {
            lastWarning = nil
        }
    }

    /// Re-reads authorization + shield state without prompting. Called on launch
    /// and when the scene becomes active.
    func refreshScreenTimeState() async {
        screenTimeStatus = await screenTime.refreshAuthorizationStatus()
        preferences.set(screenTimeStatus.rawValue, for: .screenTimeAuthorizationStatus)
        screenTimeManager.reconcileOnLaunch()
    }

    var isScreenTimeEntitlementAvailable: Bool { screenTime.isEntitlementAvailable }

    // MARK: - Emergency

    /// Starts the cooling window. Mirrors `startEmergencyCoolDown`: the clock
    /// starts immediately and no token can be generated until it reaches zero.
    func beginEmergencyCoolDown(now: Date = Date()) {
        emergencyState = .cooling
        emergencyCoolDownRemaining = Int(EmergencyDomain.cooldownDuration)
    }

    /// Advances the cooling countdown; the caller drives this from a timer.
    func refreshEmergencyCoolDown(cooldownStart: Date, now: Date = Date()) {
        guard emergencyState == .cooling else { return }
        if EmergencyDomain.isCooldownComplete(cooldownStart: cooldownStart, now: now) {
            emergencyCoolDownRemaining = 0
            emergencyState = .readyToRequest
        } else {
            emergencyCoolDownRemaining = EmergencyDomain.coolingRemaining(cooldownStart: cooldownStart, now: now)
        }
    }

    /// Records the unlock request, starting the 60-minute token-validity window.
    func requestEmergencyUnlock(now: Date = Date()) {
        emergencyState = .requested
        screenTimeManager.beginEmergencyRequest(now: now)
    }

    /// Authorizes a token and applies its real effect (suspend shields only for a
    /// valid, non-decoy token).
    @discardableResult
    func authorizeEmergencyToken(decodedSuccessfully: Bool, isDecoy: Bool, now: Date = Date()) -> EmergencyDomain.AuthorizationResult {
        let result = screenTimeManager.authorizeEmergencyToken(
            decodedSuccessfully: decodedSuccessfully,
            isDecoy: isDecoy,
            now: now
        )
        if result.shouldSuspendShield {
            emergencyState = .activeUnlocked
        }
        return result
    }

    /// Ends the emergency window and re-arms the shield (re-entry path).
    func endEmergencyUnlock() {
        emergencyState = .locked
        emergencyCoolDownRemaining = 0
        screenTimeManager.endEmergencyWindow()
    }

    // MARK: - Anchor Ritual

    /// Starts a session through the domain, applying its ledger effect on
    /// completion. Throws `AnchorRitual.RitualError` when the duration is capped.
    func startRitual(durationMinutes: Int, now: Date = Date()) throws {
        rollRitualCountersIfNeeded(now: now)
        ritual = try AnchorRitual.start(
            durationMinutes: durationMinutes,
            counters: ritualDailyCounters
        )
    }

    /// Completes the session and credits the domain-computed points.
    func completeRitual(now: Date = Date()) throws {
        rollRitualCountersIfNeeded(now: now)
        let completion = try AnchorRitual.complete(&ritual, counters: ritualDailyCounters)
        preferences.set(completion.shortSessionCount, for: .dailyShortSessionCount)
        preferences.set(completion.hasLongSessionToday, for: .dailyLongSession)
        preferences.set(completion.reflectionCount, for: .dailyReflectionCount)
        addPoints(completion.points, reason: "Completed \(completion.durationMinutes)m Eraser Protocol", category: "focus")
    }

    func cancelRitual() {
        AnchorRitual.cancel(&ritual)
    }

    /// Feeds the derived face-down decision from the motion adapter into the
    /// domain, which owns the pickup debounce and counting rule.
    func updateRitualOrientation(isFaceDown: Bool, now: Date = Date()) {
        AnchorRitual.updateOrientation(&ritual, isFaceDown: isFaceDown, at: now)
    }

    /// Resets the daily counters when the calendar day changes, mirroring how
    /// Android's per-date preference keys expire naturally.
    private func rollRitualCountersIfNeeded(now: Date) {
        let key = Self.dayKey(now)
        guard preferences.string(.ritualCountersDate) != key else { return }
        preferences.set(key, for: .ritualCountersDate)
        preferences.set(0, for: .dailyShortSessionCount)
        preferences.set(false, for: .dailyLongSession)
        preferences.set(0, for: .dailyReflectionCount)
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private var ritualDailyCounters: AnchorRitual.DailyCounters {
        AnchorRitual.DailyCounters(
            shortSessionCount: preferences.int(.dailyShortSessionCount),
            hasLongSessionToday: preferences.bool(.dailyLongSession),
            reflectionCount: preferences.int(.dailyReflectionCount)
        )
    }

    // MARK: - Partner

    /// Starts a partner session in the `pending` state, mirroring Android's
    /// challenge launch. It must be activated (via the companion broadcast on
    /// Android, via the connect flow here) within the grace window or it settles
    /// as a broken covenant.
    func beginPartnerSession(partnerName: String, durationMinutes: Int = PartnerDomain.defaultDurationMinutes, now: Date = Date()) {
        partnerSession = PartnerDomain.Session(
            partnerName: partnerName,
            status: .pending,
            startedAt: now,
            durationMinutes: durationMinutes
        )
    }

    /// Settles a completed partner outing through the domain.
    func settlePartnerCompletion(isSuccess: Bool, isGroup: Bool, partnerName: String, durationMinutes: Int) {
        let settlement = PartnerDomain.settleCompletion(
            isSuccess: isSuccess,
            isGroup: isGroup,
            partnerName: partnerName,
            durationMinutes: durationMinutes
        )
        if settlement.points >= 0 {
            addPoints(settlement.points, reason: settlement.reason, category: "outdoor")
        } else {
            deductPoints(-settlement.points, reason: settlement.reason, category: "penalty")
        }
        partnerSession = nil
    }

    /// Applies the pending-session-expiry penalty and raises the guilt banner,
    /// mirroring `handlePartnerSessionPendingExpired`.
    func handlePartnerSessionPendingExpired(now: Date = Date()) {
        guard let session = partnerSession,
              let settlement = PartnerDomain.settlementForExpiredPendingSession(session, now: now) else { return }
        deductPoints(-settlement.points, reason: settlement.reason, category: settlement.status)
        partnerSession = nil
        showPartnerCovenantGuiltBanner = true
    }

    func dismissPartnerCovenantGuiltBanner() {
        showPartnerCovenantGuiltBanner = false
    }
}
