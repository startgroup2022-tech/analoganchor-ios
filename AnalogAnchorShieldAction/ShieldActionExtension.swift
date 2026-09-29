import Foundation
import ManagedSettings
import AnalogAnchorKit

/// Shield Action extension.
///
/// Handles the two buttons defined by the Shield Configuration extension. Apple
/// only allows a shield action to `close`, `defer` (let the shield reappear on
/// next launch), or open the host app via a custom URL scheme — there is no
/// supported "unblock itself" behaviour, so none is attempted here.
///
/// - Primary button → open Analog Anchor so the user can deliberately review or
///   change the rule (URL scheme `analoganchor://dayguard`).
/// - Secondary button → defer (a real pause, not a bypass).
final class ShieldActionExtension: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: Application,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for application: Application,
        in category: ActivityCategory,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomain,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomain,
        in category: ActivityCategory,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // Open the app; the shield stays applied until the user changes the
            // rule there. Records the event for the app's diagnostics view.
            var store = SharedPolicyStore()
            store.appendDiagnostic(.init(
                severity: .info,
                source: "shield-action",
                message: "User opened Analog Anchor from a shield."
            ))
            completionHandler(.openParentApplication)
        case .secondaryButtonPressed:
            // A deliberate pause — the shield returns on the next launch.
            completionHandler(.defer)
        @unknown default:
            completionHandler(.close)
        }
    }
}
