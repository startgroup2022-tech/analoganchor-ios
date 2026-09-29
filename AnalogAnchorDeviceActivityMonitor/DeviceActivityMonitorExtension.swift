import Foundation
import DeviceActivity
import ManagedSettings
import FamilyControls
import AnalogAnchorKit

/// DeviceActivity Monitor extension.
///
/// Receives the `DeviceActivitySchedule` / `DeviceActivityEvent` callbacks that
/// `DeviceActivityScheduler` registered, then applies or clears shields through
/// ManagedSettings. Because this runs in its own process, it reads the policy
/// and the picker selection from the App Group (never the main app's memory).
///
/// Boundaries are honest about Apple's model: event callbacks fire at
/// *thresholds*, not on every usage tick, so the shield is applied the moment a
/// limit/window crosses rather than continuously measured.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .analogAnchorPrimary)
    private var policyStore = SharedPolicyStore()

    // MARK: - Window schedules

    override func intervalDidStart(for activity: DeviceActivityName) {
        // A blocked window (bedtime / wind-down / Fajr lockdown) opened: shield.
        guard let policy = policyStore.loadPolicy(), policy.isEnabled else { return }
        let ruleID = ruleID(from: activity)
        applyShield(selection: policyStore.loadSelection(), reason: "window-start:\(activity.rawValue)")
        policyStore.saveEngineState(.init(
            activeCause: ruleID.map { .window(ruleID: $0) },
            updatedAt: Date()
        ))
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        // A window closed. Re-derive from policy instead of blindly clearing:
        // another window may still be open, or a daily limit may hold the shield.
        guard let policy = policyStore.loadPolicy(), policy.isEnabled else {
            clearShield()
            policyStore.saveEngineState(.idle)
            return
        }

        if let stillOpen = policy.firstOpenWindow(at: Date()) {
            applyShield(selection: policyStore.loadSelection(), reason: "overlap:\(activity.rawValue)")
            policyStore.saveEngineState(.init(activeCause: .window(ruleID: stillOpen.id), updatedAt: Date()))
            record("window-end-overlap:\(activity.rawValue)")
            return
        }

        if case .dailyLimit = policyStore.loadEngineState()?.activeCause {
            record("window-end-keep-limit:\(activity.rawValue)")
            return
        }

        clearShield()
        policyStore.saveEngineState(.idle)
        record("window-end:\(activity.rawValue)")
    }

    // MARK: - Threshold events

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        guard let policy = policyStore.loadPolicy(), policy.isEnabled else { return }
        applyShield(selection: policyStore.loadSelection(), reason: "threshold:\(event.rawValue)")
        // The daily limit becomes the cause; it outlives any single window.
        let limitID = policy.dailyLimitRules.first?.id
        policyStore.saveEngineState(.init(
            activeCause: limitID.map { .dailyLimit(ruleID: $0) },
            updatedAt: Date()
        ))
    }

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        // Warning lead-in: record only. We deliberately do not shield early —
        // the strict ceiling is the threshold itself.
        record("warning:\(event.rawValue)")
    }

    // MARK: - Shield application

    private func applyShield(selection: ScreenTimeSelectionPayload, reason: String) {
        guard let data = selection.rawSelectionJSON,
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            record("no-selection:\(reason)")
            return
        }

        store.shield.applications = decoded.applicationTokens.isEmpty ? nil : decoded.applicationTokens
        store.shield.applicationCategories = decoded.categoryTokens.isEmpty
            ? nil
            : .specific(decoded.categoryTokens)
        store.shield.webDomainCategories = decoded.webDomainTokens.isEmpty
            ? nil
            : .specific(decoded.webDomainTokens)
        record("shielded:\(reason)")
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
    }

    /// Extracts the rule UUID from a window activity name of the form
    /// `<prefix>.window.<uuid>.<weekday>`.
    private func ruleID(from activity: DeviceActivityName) -> UUID? {
        let parts = activity.rawValue.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        return UUID(uuidString: String(parts[parts.count - 2]))
    }

    // MARK: - Diagnostics

    private func record(_ message: String) {
        policyStore.appendDiagnostic(.init(severity: .info, source: "monitor", message: message))
    }
}

extension ManagedSettingsStore.Name {
    /// Same shared store name as the app target (`AnalogAnchorConfig`), so
    /// shields applied here are the ones the app clears and vice versa.
    static let analogAnchorPrimary = Self(AnalogAnchorConfig.managedSettingsStoreName)
}
