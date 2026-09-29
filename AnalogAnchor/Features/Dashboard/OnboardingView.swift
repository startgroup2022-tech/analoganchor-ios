import SwiftUI
import AnalogAnchorKit

/// Onboarding — mirrors the Android 4-step flow (welcome → physical anchors →
/// permissions → begin), condensed into the foundation.
struct OnboardingView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @State private var step = 1
    private let totalSteps = 3

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text("\(step) of \(totalSteps)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                    Spacer()
                    languageToggle
                }

                ProgressView(value: Double(step), total: Double(totalSteps))
                    .tint(AATheme.glowGreen)

                Spacer()

                Group {
                    switch step {
                    case 1: welcomeStep
                    case 2: anchorsStep
                    default: beginStep
                    }
                }
                .transition(.opacity)

                Spacer()

                HStack(spacing: 12) {
                    if step > 1 {
                        Button(L10n.text(.onboardContinue, isEnglish: environment.isEnglish)) {
                            withAnimation { step -= 1 }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AATheme.mutedSilver)
                    }
                    PremiumButton(
                        title: step < totalSteps
                            ? L10n.text(.onboardContinue, isEnglish: environment.isEnglish)
                            : L10n.text(.onboardBegin, isEnglish: environment.isEnglish),
                        systemImage: step < totalSteps ? "arrow.right" : "checkmark"
                    ) {
                        if step < totalSteps {
                            withAnimation { step += 1 }
                        } else {
                            environment.completeOnboarding()
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var languageToggle: some View {
        Button {
            environment.setEnglish(!environment.isEnglish)
        } label: {
            Text(environment.isEnglish ? L10n.text(.arabic, isEnglish: true) : L10n.text(.english, isEnglish: false))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(AATheme.obsidianGlass))
                .foregroundStyle(AATheme.glowGreen)
        }
        .buttonStyle(.plain)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "anchor")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(AATheme.glowGreenGradient)
            Text(L10n.text(.onboardWelcome, isEnglish: environment.isEnglish))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(AATheme.warmOffWhite)
            Text(L10n.text(.onboardBody, isEnglish: environment.isEnglish))
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(AATheme.mutedSilver)
        }
    }

    private var anchorsStep: some View {
        VStack(spacing: 14) {
            Text(environment.isEnglish ? "The Physical Anchors" : "المراسي المادية")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(AATheme.warmOffWhite)
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    anchorRow(icon: "wave.3.right", title: "NFC Anchor Tag", detail: environment.isEnglish ? "Desk + Fajr eraser tags" : "وسم المكتب + ممحاة الفجر")
                    anchorRow(icon: "figure.walk", title: "Motion & Steps", detail: environment.isEnglish ? "Wake proof + walks" : "إثبات الاستيقاظ + المشي")
                    anchorRow(icon: "mappin.and.ellipse", title: "Sanctuary Geofence", detail: environment.isEnglish ? "Mosque + outdoor hubs" : "المسجد + الوجهات الخارجية")
                    anchorRow(icon: "camera", title: "Whiteboard Proof", detail: environment.isEnglish ? "Analog photo evidence" : "إثبات بالصورة")
                }
            }
        }
    }

    private var beginStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(AATheme.glowGreenGradient)
            Text(environment.isEnglish ? "You're ready" : "أنت جاهز")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(AATheme.warmOffWhite)
            Text(environment.isEnglish
                 ? "Permissions are requested only when you open a feature that needs them."
                 : "لا تُطلب الأذونات إلا عند فتح ميزة تحتاجها.")
                .font(.system(size: 14, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(AATheme.mutedSilver)
        }
    }

    private func anchorRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AATheme.glowGreen)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(AATheme.warmOffWhite)
                Text(detail).font(.system(size: 12, design: .rounded)).foregroundStyle(AATheme.mutedSilver)
            }
            Spacer()
        }
    }
}
