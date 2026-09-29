import Foundation
import AnalogAnchorKit

#if canImport(FamilyControls)
import FamilyControls
#endif

/// Real Family Controls authorization coordinator.
///
/// Flow:  App → ScreenTimeCoordinator → AuthorizationCenter → FamilyControls.
///
/// This type performs **authorization only**. Shield application, schedules and
/// the picker live in `ScreenTimeManager` / `DeviceActivityScheduler` so no
/// privileged API leaks into the view layer.
///
/// Every failure is reported (`ScreenTimeAuthorizationOutcome.error`); nothing
/// is faked as "approved" when the system did not say so.
@MainActor
final class ScreenTimeCoordinator: ScreenTimeAuthorizing {

    private(set) var status: ScreenTimeAuthorizationStatus = .notDetermined

    /// Last error from an authorization attempt, for the UI to explain.
    private(set) var lastError: ScreenTimeAuthorizationError?

    /// True only when the FamilyControls framework is linked into this build.
    /// The entitlement itself is validated by the OS at request time.
    let isEntitlementAvailable: Bool

    init() {
        #if canImport(FamilyControls)
        self.isEntitlementAvailable = true
        #else
        self.isEntitlementAvailable = false
        #endif
        self.status = readPersistedStatus()
    }

    // MARK: - Request

    @discardableResult
    func requestAuthorization() async -> ScreenTimeAuthorizationOutcome {
        #if canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            status = .approved
            lastError = nil
        } catch {
            // The system throws on user refusal *and* when the entitlement is
            // missing. Distinguish the two as far as the API allows so the UI
            // can point at the right fix (Settings vs. provisioning profile).
            let message = String(describing: error)
            if message.localizedCaseInsensitiveContains("entitlement")
                || message.localizedCaseInsensitiveContains("not authorized") {
                status = .unavailable
                lastError = .entitlementMissing
            } else {
                status = .denied
                lastError = .systemError(message)
            }
        }
        #else
        status = .unavailable
        lastError = .frameworkUnavailable
        #endif

        persist(status)
        return ScreenTimeAuthorizationOutcome(status: status, error: lastError)
    }

    // MARK: - Refresh

    /// Reads the current status from `AuthorizationCenter` without prompting.
    /// A user can revoke Screen Time access at any time in Settings, so this is
    /// called on launch and whenever the app returns to the foreground.
    @discardableResult
    func refreshAuthorizationStatus() async -> ScreenTimeAuthorizationStatus {
        #if canImport(FamilyControls)
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined: status = .notDetermined
        case .denied: status = .denied
        case .approved: status = .approved
        @unknown default: status = .unavailable
        }
        #else
        status = .unavailable
        #endif
        persist(status)
        return status
    }

    // MARK: - Persistence

    private func persist(_ status: ScreenTimeAuthorizationStatus) {
        PreferencesStore().set(status.rawValue, for: .screenTimeAuthorizationStatus)
    }

    private func readPersistedStatus() -> ScreenTimeAuthorizationStatus {
        guard let raw = PreferencesStore().string(.screenTimeAuthorizationStatus),
              let value = ScreenTimeAuthorizationStatus(rawValue: raw) else {
            return .notDetermined
        }
        return value
    }
}
