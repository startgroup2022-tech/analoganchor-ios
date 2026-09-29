import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Shield Configuration extension.
///
/// Renders the screen shown when the user tries to open a shielded app. The
/// design is unmistakably Analog Anchor — it never imitates a system dialog.
/// The copy states plainly that the block was set by the user in this app and
/// how to change it, which is what App Review expects.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(title: application.localizedDisplayName)
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration(title: category.localizedDisplayName ?? application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(title: webDomain.domain)
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration(title: webDomain.domain ?? category.localizedDisplayName)
    }

    private func makeConfiguration(title: String?) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundColor: UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0),
            icon: UIImage(systemName: "anchor"),
            title: ShieldConfiguration.Label(
                text: "ANALOG ANCHOR",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitleText(for: title),
                color: UIColor(white: 0.75, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "OPEN ANALOG ANCHOR",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.20, green: 0.78, blue: 0.55, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "TAKE A BREATH",
                color: UIColor(white: 0.7, alpha: 1.0)
            )
        )
    }

    /// Honest, user-authored framing: this shield is the user's own rule, not an
    /// Apple system restriction. The "take a breath" line is a real pause, not a
    /// bypass.
    private func subtitleText(for title: String?) -> String {
        let app = title.map { "\($0) is" } ?? "This app is"
        return "\(app) resting by your own Day Guard rule. Take a breath, then open Analog Anchor if this is deliberate."
    }
}
