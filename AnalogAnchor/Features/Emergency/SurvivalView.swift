import SwiftUI
import AnalogAnchorKit

/// Survival Kit — the calm, low-friction support screen shown during the
/// cooling window. Content mirrors the web survival kit intent (breathing
/// guide + reflection prompts), fully offline.
struct SurvivalView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var breathPhase = 0
    @State private var breathing = false
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                AATheme.premiumBackdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        breathingCard
                        promptsCard
                        webLink
                    }
                    .padding(18)
                }
            }
            .navigationTitle(L10n.text(.survivalTitle, isEnglish: environment.isEnglish))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(environment.isEnglish ? "Close" : "إغلاق") { dismiss() }
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var breathingCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                SectionHeader(title: environment.isEnglish ? "5-Second Breathing Wave" : "موجة التنفس ٥ ثوانٍ",
                              subtitle: environment.isEnglish ? "2.5s inhale · 2.5s exhale" : "٢٫٥ شهيق · ٢٫٥ زفير")
                ZStack {
                    Circle()
                        .fill(AATheme.glowGreen.opacity(0.15))
                        .frame(width: breathing ? 160 : 100, height: breathing ? 160 : 100)
                        .animation(.easeInOut(duration: 2.5), value: breathing)
                    Text(breathing ? (environment.isEnglish ? "Exhale" : "زفير") : (environment.isEnglish ? "Inhale" : "شهيق"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AATheme.glowGreen)
                }
                .frame(height: 180)
                PremiumButton(title: breathing ? (environment.isEnglish ? "Stop" : "إيقاف") : (environment.isEnglish ? "Begin Breathing" : "ابدأ التنفس")) {
                    toggleBreathing()
                }
            }
        }
    }

    private var promptsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Reflection Prompts" : "أسئلة للتأمل")
                prompt(environment.isEnglish ? "What am I actually reaching for right now?" : "ما الذي أسعى إليه فعلًا الآن؟")
                prompt(environment.isEnglish ? "Will this matter in one hour?" : "هل سيؤثر هذا بعد ساعة؟")
                prompt(environment.isEnglish ? "Cravings peak and pass within 20–40 minutes." : "تصل الرغبة ذروتها ثم تخف خلال ٢٠–٤٠ دقيقة.")
            }
        }
    }

    private var webLink: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: environment.isEnglish ? "Full Survival Kit" : "عدة النجاة الكاملة")
                Text(environment.isEnglish
                     ? "Breathing guides, reflection prompts and soothing audio are hosted on the web kit."
                     : "أدلة التنفس وأسئلة التأمل والصوت الهادئ متاحة على النسخة الإلكترونية.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
                Link(destination: AnalogAnchorConfig.survivalKitURL) {
                    Text(environment.isEnglish ? "Open get-analog-anchor.com/survivalkit" : "افتح get-analog-anchor.com/survivalkit")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AATheme.glowGreen)
                }
            }
        }
    }

    private func prompt(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.dotted").foregroundStyle(AATheme.glowGreen)
            Text(text).font(.system(size: 13, design: .rounded)).foregroundStyle(AATheme.warmOffWhite)
        }
    }

    private func toggleBreathing() {
        breathing.toggle()
        timer?.invalidate()
        guard breathing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task { @MainActor in
                breathing.toggle()
            }
        }
    }
}
