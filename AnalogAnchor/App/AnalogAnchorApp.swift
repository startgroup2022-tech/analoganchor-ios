import SwiftUI
import AnalogAnchorKit

/// Analog Anchor (iOS) application entry point.
///
/// Phase 3 wires the real Screen Time engine: Family Controls authorization,
/// `FamilyActivityPicker` selection, `DeviceActivity` schedules and
/// `ManagedSettings` shields, plus three embedded extensions (Shield
/// Configuration, Shield Action, DeviceActivity Monitor).
@main
struct AnalogAnchorApp: App {

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var environment: AppEnvironment
    @StateObject private var location = LocationService()
    @StateObject private var motion = MotionService()
    @StateObject private var nfc = NFCService()
    @StateObject private var haptics = HapticsService()
    @StateObject private var notifications = NotificationService()
    @StateObject private var fajr = FajrService()
    @StateObject private var partner = PartnerBluetoothTransport()
    @StateObject private var mosque = MosqueLookupService()

    init() {
        // One coordinator, one authorization state. `AppEnvironment` owns it and
        // hands the *same* instance to `BehaviorReportProvider`, so the provider's
        // "is authorized" check and the UI's status can never disagree.
        let coordinator = ScreenTimeCoordinator()
        let provider = BehaviorReportProvider(isAuthorized: { [weak coordinator] in
            coordinator?.status == .approved
        })
        _environment = StateObject(wrappedValue: AppEnvironment(
            screenTime: coordinator,
            behaviorProvider: provider
        ))
    }

    /// Shared SwiftData container (app + future extensions). Falls back to an
    /// in-memory container if the persistent store cannot be created so the app
    /// always launches.
    private let modelContainer: ModelContainer? = {
        #if canImport(SwiftData)
        return try? StorageContainer.makeModelContainer()
        #else
        return nil
        #endif
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(location)
                .environmentObject(motion)
                .environmentObject(nfc)
                .environmentObject(haptics)
                .environmentObject(notifications)
                .environmentObject(fajr)
                .environmentObject(partner)
                .environmentObject(mosque)
                .onReceive(NotificationCenter.default.publisher(for: .aaFajrAlarmDismissed)) { _ in
                    // The "Verify Wake" action on the Fajr alarm arms the wake proof.
                    fajr.recordAlarmDismissed()
                }
                .preferredColorScheme(.dark)
                .environment(\.layoutDirection, environment.isEnglish ? .leftToRight : .rightToLeft)
                .task {
                    // Configure categories only. Notification permission is
                    // requested contextually (from Mosque settings or when the
                    // user first schedules reminders), never on first launch.
                    await notifications.configure()
                    environment.recalculatePrayerTimes()
                    environment.runWeeklyMaintenanceIfNeeded()
                    // Re-read Screen Time authorization and re-apply shields in
                    // case the policy survived a process restart.
                    await environment.refreshScreenTimeState()
                    // Attach the Fajr coordinator to the live platform services and
                    // credit the wake proof through the ledger when it is earned.
                    fajr.attach(motion: motion, notifications: notifications)
                    fajr.onWakeProofEarned = { points, reason in
                        environment.addPoints(points, reason: reason, category: "fajr")
                    }
                    fajr.reloadDailyState()
                    // Schedule today's Fajr reminder from the real prayer times so
                    // the wake-proof flow has a real trigger.
                    if let times = environment.prayerTimes {
                        await fajr.scheduleFajr(for: times, isEnglish: environment.isEnglish)
                        fajr.evaluateMissedIfDue(times: times)
                    }
                }
        }
        .modelContainer(modelContainer ?? Self.inMemoryFallback())
        .onChange(of: scenePhase) { _, phase in
            // The user can revoke Screen Time access or change usage in Settings
            // at any time, so re-check whenever the app becomes active.
            guard phase == .active else { return }
            Task { await environment.refreshScreenTimeState() }
            // A pending partner session that was never activated settles as a
            // broken covenant once its grace window lapses — Android did this on
            // resume; here the same check runs on foreground.
            environment.handlePartnerSessionPendingExpired()
            fajr.reloadDailyState()
            if let times = environment.prayerTimes {
                fajr.evaluateMissedIfDue(times: times)
            }
        }
    }

    private static func inMemoryFallback() -> ModelContainer {
        #if canImport(SwiftData)
        return try! StorageContainer.makeModelContainer(inMemory: true)
        #else
        fatalError("SwiftData unavailable")
        #endif
    }
}
