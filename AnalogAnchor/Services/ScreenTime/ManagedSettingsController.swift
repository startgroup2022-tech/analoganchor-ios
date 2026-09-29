import Foundation
import AnalogAnchorKit

#if canImport(ManagedSettings)
import ManagedSettings
#endif

#if canImport(FamilyControls)
import FamilyControls
#endif

/// Owns the single `ManagedSettingsStore` used for shields.
///
/// ## Separation of concerns
/// SwiftUI never touches ManagedSettings: the view layer edits a
/// `ScreenTimePolicy`, `ScreenTimeManager` decides *whether* shielding should be
/// on, and this controller is the only place that writes to the store.
///
/// Application tokens come exclusively from `FamilyActivityPicker` (stored in
/// the App Group); the app never enumerates installed apps or bundle IDs.
@MainActor
final class ManagedSettingsController {

    /// All app/category shielding is written through one named store so it can be
    /// cleared atomically and never collides with another feature's defaults.
    #if canImport(ManagedSettings)
    private let store = ManagedSettingsStore(named: .analogAnchor)
    #endif

    /// Applies shields for the given selection. Passing an empty selection
    /// clears them.
    ///
    /// - Returns: `true` when the shield state now matches the request.
    @discardableResult
    func applyShield(selection: ScreenTimeSelectionPayload, reason: String) -> Bool {
        #if canImport(ManagedSettings) && canImport(FamilyControls)
        let decoded = ScreenTimeSelectionCodec.decode(selection)
        if decoded.applicationTokens.isEmpty && decoded.categoryTokens.isEmpty {
            clearShield()
            return true
        }
        store.shield.applications = decoded.applicationTokens.isEmpty ? nil : decoded.applicationTokens
        store.shield.applicationCategories = decoded.categoryTokens.isEmpty
            ? nil
            : .specific(decoded.categoryTokens)
        store.shield.webDomainCategories = decoded.webDomainTokens.isEmpty
            ? nil
            : .specific(decoded.webDomainTokens)
        return true
        #else
        return false
        #endif
    }

    /// Removes every Analog Anchor shield.
    func clearShield() {
        #if canImport(ManagedSettings)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        #endif
    }

    /// Whether any shield is currently applied to a selection.
    func hasActiveShield() -> Bool {
        #if canImport(ManagedSettings)
        return store.shield.applications != nil
            || store.shield.applicationCategories != nil
            || store.shield.webDomainCategories != nil
        #else
        return false
        #endif
    }
}

#if canImport(ManagedSettings)
extension ManagedSettingsStore.Name {
    /// Dedicated store shared by the app and every extension so shields applied
    /// by one process are visible to (and clearable by) the others.
    static let analogAnchor = Self(AnalogAnchorConfig.managedSettingsStoreName)
}
#endif
