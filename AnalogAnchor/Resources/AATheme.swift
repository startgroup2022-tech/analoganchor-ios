import SwiftUI

/// Analog Anchor design tokens — a direct port of the Android `Color.kt` /
/// `ZenithColor.kt` palette so the iOS build preserves the identical visual
/// identity (Obsidian / GlowGreen / cyan aura), in both dark and light modes.
///
/// Colours are defined as dynamic values via asset-catalog-free
/// `Color(UIColor { traits in ... })` so light/dark switching matches Android's
/// global `isDarkThemeGlobal` getters.
enum AATheme {

    // MARK: - Dynamic helper

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #else
        return Color(hex: dark)
        #endif
    }

    // MARK: - Palette (values mirror Android exactly)

    static let obsidianBg = dynamic(0xF3F8FA, 0x0B1012)
    static let obsidianSurface = dynamic(0xFFFFFF, 0x11191D)
    static let deepPanel = dynamic(0xE6EDF0, 0x172126)
    static let obsidianBorder = dynamic(0xCFDCE1, 0x2B3A40)
    static let steelShadow = dynamic(0x8BA0A8, 0x4E5C62)
    static let mutedSilver = dynamic(0x4E5C62, 0xA2AFB6)
    static let warmOffWhite = dynamic(0x0B1012, 0xF3F8FA)
    static let warmSilverText = dynamic(0x2B3A40, 0xD1DCE1)
    static let brushedSteel = dynamic(0x2B3A40, 0xC4D0D5)

    static let refinedGreen = dynamic(0x007A8C, 0x76E8F7)
    static let glowGreen = dynamic(0x00808F, 0x7DEEFF)
    static let cyanAura = dynamic(0x009688, 0x1FE6FF)
    static let signalAmber = dynamic(0xD84315, 0xF3B65C)
    static let signalRed = dynamic(0xD32F2F, 0xFF5252)

    static let obsidianGlass = dynamic(0x12009688, 0x121FE6FF)
    static let obsidianGlowBg = dynamic(0xEAF1F3, 0x081013)
    static let glowGreenMuted = dynamic(0x1A00808F, 0x1A7DEEFF)
    static let signalAmberMuted = dynamic(0x1AD84315, 0x1AF3B65C)
    static let signalRedMuted = dynamic(0x1AD32F2F, 0x1AFF5252)
    static let obsidianBorderMuted = dynamic(0x33CFDCE1, 0x332B3A40)

    // MARK: - Gradients

    static var glowGreenGradient: LinearGradient {
        LinearGradient(colors: [glowGreen, cyanAura], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var signalAmberGradient: LinearGradient {
        LinearGradient(colors: [signalAmber, signalAmber.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
    }

    static var steelGradient: LinearGradient {
        LinearGradient(colors: [warmOffWhite, mutedSilver], startPoint: .top, endPoint: .bottom)
    }

    static var premiumBackdrop: RadialGradient {
        RadialGradient(colors: [deepPanel, obsidianBg], center: .top, startRadius: 20, endRadius: 900)
    }
}

// MARK: - Hex helpers

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}
