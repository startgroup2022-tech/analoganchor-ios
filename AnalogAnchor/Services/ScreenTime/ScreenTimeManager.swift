import Foundation
import Combine
import AnalogAnchorKit

/// The single entry point the UI uses to drive Screen Time.
///
/// Layering (never bypassed):
/// ```
/// UI (SwiftUI)
///   ↓
/// ScreenTimeManager      ← policy decisions, error surface
///   ↓
/// DeviceActivityScheduler / ManagedSettingsController   ← Apple frameworks
/// ```
///
/// The manager never imports SwiftUI and the views never import ManagedSettings,
/// so the policy is testable and the privileged calls stay in one place.
@MainActor
final class ScreenTimeManager: ObservableObject, ShieldSuspending {

    // MARK: - State surfaced to the UI

    @Published private(set) var policy: ScreenTimePolicy
    @Published private(set) var selection: ScreenTimeSelectionPayload
    @Published private(set) var lastError: String?
    @Published private(set) var isEngineActive: Bool

    // MARK: - Dependencies

    private var store: SharedPolicyStore
    private let scheduler = DeviceActivityScheduler()
    private let shielding = ManagedSettingsController()

    init(store: SharedPolicyStore = SharedPolicyStore()) {
        self.store = store
        self.policy = store.loadPolicy() ?? ScreenTimePolicy()
        self.selection = store.loadSelection()
        self.isEngineActive = store.loadPolicy()?.isEnabled ?? false
    }

    // MARK: - Selection

    /// Persists a picker selection (opaque tokens) into the App Group.
    func updateSelection(_ payload: ScreenTimeSelectionPayload) {
        selection = payload
        if store.saveSelection(payload) == false {
            lastError = store.lastError?.localizedDescription
                ?? "Could not save the app selection to the App Group container."
        }
    }

    // MARK: - Policy editing

    /// Adds a validated rule, rejecting invalid schedules with a clear error.
    /// A duplicate `id` is rejected too, because schedules are keyed by rule id
    /// in the shared store and in DeviceActivity activity names.
    @discardableResult
    func addRule(_ rule: ScreenTimePolicy.Rule) -> Bool {
        do {
            try ScreenTimePolicy.validate(rule)
        } catch {
            lastError = (error as? ScreenTimePolicy.ValidationError).map(describe) ?? "\(error)"
            return false
        }
        guard !policy.rules.contains(where: { $0.id == rule.id }) else {
            lastError = "A rule with this identifier already exists."
            return false
        }
        policy.rules.append(rule)
        policy.updatedAt = Date()
        return persist()
    }

    func removeRule(id: UUID) {
        policy.rules.removeAll { $0.id == id }
        policy.updatedAt = Date()
        persist()
    }

    func setRuleEnabled(id: UUID, enabled: Bool) {
        guard let index = policy.rules.firstIndex(where: { $0.id == id }) else { return }
        policy.rules[index].isEnabled = enabled
        policy.updatedAt = Date()
        persist()
    }

    // MARK: - Activation

    /// Turns the engine on/off. Activating registers schedules and applies the
    /// shield; deactivating clears both. Returns `false` and sets `lastError`
    /// when the OS refuses.
    @discardableResult
    func setEngineActive(_ active: Bool) -> Bool {
        if active {
            // A policy with no selection can't shield anything — say so instead
            // of silently doing nothing.
            guard !selection.isEmpty else {
                lastError = "Select at least one app or category before activating Day Guard."
                return false
            }
        }

        policy.isEnabled = active
        policy.updatedAt = Date()
        guard persist() else { return false }

        do {
            try scheduler.reschedule(policy: policy, selection: selection)
        } catch {
            lastError = error.localizedDescription
            return false
        }

        if active {
            // The engine enforces *windows* and *daily limits*, not "block
            // forever". The app therefore shields immediately only when a
            // blocked window is open right now; otherwise the DeviceActivity
            // monitor applies the shield at the real start/threshold moment.
            if let openWindow = policy.firstOpenWindow(at: Date()) {
                _ = shielding.applyShield(selection: selection, reason: "engine-active:window-open")
                store.saveEngineState(.init(
                    activeCause: .window(ruleID: openWindow.id),
                    updatedAt: Date()
                ))
            } else {
                shielding.clearShield()
                store.saveEngineState(.idle)
            }
        } else {
            shielding.clearShield()
            store.saveEngineState(.idle)
        }
        isEngineActive = active
        lastError = nil
        return true
    }

    /// Re-applies schedules + shield from the current policy. Called on launch
    /// and when returning to the foreground so state survives process restarts.
    func reconcileOnLaunch() {
        guard policy.isEnabled, !selection.isEmpty else { return }
        do {
            try scheduler.reschedule(policy: policy, selection: selection)
        } catch {
            lastError = error.localizedDescription
            return
        }
        // Re-derive the shield from the policy rather than forcing one: if a
        // window is open, restore the shield; otherwise leave it clear (a daily
        // limit shield, if any, is re-applied by the monitor at threshold).
        if let openWindow = policy.firstOpenWindow(at: Date()) {
            _ = shielding.applyShield(selection: selection, reason: "reconciled:window-open")
            store.saveEngineState(.init(activeCause: .window(ruleID: openWindow.id), updatedAt: Date()))
        } else if case .dailyLimit = store.loadEngineState()?.activeCause {
            // A daily-limit shield was active when the app last ran; keep it.
            _ = shielding.applyShield(selection: selection, reason: "reconciled:daily-limit")
        } else {
            shielding.clearShield()
            store.saveEngineState(.idle)
        }
    }

    /// Clears shields without touching the saved policy (emergency/expiry path).
    /// Cancels the DeviceActivity schedules too, so the monitor cannot re-shield
    /// while the emergency window is open.
    func suspendShields() {
        shielding.clearShield()
        scheduler.cancelAll()
    }

    /// Re-applies shields + schedules from the stored policy. The counterpart to
    /// `suspendShields()`: called when an emergency window closes or a re-entry
    /// grace period begins.
    func restoreShields() {
        guard policy.isEnabled, !selection.isEmpty else { return }
        do {
            try scheduler.reschedule(policy: policy, selection: selection)
        } catch {
            lastError = error.localizedDescription
            return
        }
        if let openWindow = policy.firstOpenWindow(at: Date()) {
            _ = shielding.applyShield(selection: selection, reason: "restored:window-open")
            store.saveEngineState(.init(activeCause: .window(ruleID: openWindow.id), updatedAt: Date()))
        } else {
            shielding.clearShield()
            store.saveEngineState(.idle)
        }
    }

    // MARK: - Emergency

    /// Timestamp of the active emergency unlock request. Persisted in the App
    /// Group so the 60-minute token-validity window survives an app restart or a
    /// device reboot (the user cannot reset the clock by relaunching).
    private var emergencyRequestStart: Date? {
        get {
            let seconds = preferences.double(.emergencyRequestStart)
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        set {
            preferences.set(newValue?.timeIntervalSince1970 ?? 0, for: .emergencyRequestStart)
        }
    }

    /// Records the start of an unlock request (`requestEmergencyUnlockPayload`).
    /// The 60-minute token-validity window is measured from here.
    func beginEmergencyRequest(now: Date = Date()) {
        emergencyRequestStart = now
    }

    /// Authorizes an emergency token and lifts the shield when the domain allows.
    ///
    /// The decision itself lives in `EmergencyDomain`; this method only applies
    /// the resulting effect through the ManagedSettings adapter. A decoy token
    /// deliberately does **not** clear a real shield.
    @discardableResult
    func authorizeEmergencyToken(
        decodedSuccessfully: Bool,
        isDecoy: Bool,
        now: Date = Date()
    ) -> EmergencyDomain.AuthorizationResult {
        // Decoys are accepted even before any request exists, matching Android.
        let result = EmergencyDomain.evaluate(
            decodedSuccessfully: decodedSuccessfully,
            isDecoy: isDecoy,
            requestStart: emergencyRequestStart,
            now: now
        )
        switch result.kind {
        case .token:
            suspendShields()
            emergencyRequestStart = nil
        case .decoy:
            emergencyRequestStart = nil
        case .rejected:
            break
        }
        return result
    }

    /// Ends an emergency/active-unlock window and re-arms the shield.
    func endEmergencyWindow() {
        emergencyRequestStart = nil
        restoreShields()
    }

    // MARK: - Diagnostics

    var diagnostics: [DiagnosticRecord] { store.loadDiagnostics() }

    func clearDiagnostics() {
        store.clearDiagnostics()
    }

    // MARK: - Helpers

    private func persist() -> Bool {
        if store.savePolicy(policy) == false {
            lastError = store.lastError?.localizedDescription
                ?? "Could not save the policy to the App Group container."
            return false
        }
        return true
    }

    private func describe(_ error: ScreenTimePolicy.ValidationError) -> String {
        switch error {
        case .dailyLimitOutOfRange(let minutes):
            return "A daily limit of \(minutes) minutes is out of range (1–1440)."
        case .windowStartOutOfRange(let minutes):
            return "Window start \(minutes) is outside 00:00–23:59."
        case .windowEndOutOfRange(let minutes):
            return "Window end \(minutes) is outside 00:00–23:59."
        case .windowMissingBounds:
            return "A window needs both a start and an end time."
        case .emptySelection:
            return "Select at least one app or category."
        }
    }
}
