import SwiftUI

/// Shared, reusable UI primitives that reproduce the Android "practical
/// minimalism" language: glass cards, premium buttons, section headers.

/// Frosted glass card with the signature border + glow.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AATheme.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AATheme.obsidianBorder, lineWidth: 1)
                    )
            )
    }
}

/// Primary action button (cyan glow gradient).
struct PremiumButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(AATheme.glowGreenGradient) : AnyShapeStyle(AATheme.obsidianBorder))
            )
            .foregroundStyle(AATheme.obsidianBg)
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}

/// Small status pill used across the dashboard (e.g. "DAY GUARD").
struct StatusPill: View {
    let text: String
    var color: Color = AATheme.glowGreen

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

/// Section header with an optional trailing accessory.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(AATheme.mutedSilver)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A compact metric tile (used in the 3-up dashboard metrics grid).
struct MetricTile: View {
    let label: String
    let value: String
    var accent: Color = AATheme.glowGreen

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(AATheme.warmOffWhite)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AATheme.mutedSilver)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AATheme.deepPanel)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(accent.opacity(0.25), lineWidth: 1))
        )
    }
}

/// Progress ring for the weekly ledger.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(AATheme.obsidianBorder, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AATheme.glowGreenGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
