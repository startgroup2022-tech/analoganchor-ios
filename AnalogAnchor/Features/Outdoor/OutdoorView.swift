import SwiftUI
import AnalogAnchorKit

/// Outdoor — the "Meshwar Al-Sakeenah" walking feature.
///
/// Steps are measured with CoreMotion (Motion & Fitness permission, requested
/// lazily when the user starts a walk). Sessions of 2,000 steps award points,
/// mirroring the Android step-block logic.
struct OutdoorView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var motion: MotionService
    @EnvironmentObject private var haptics: HapticsService

    @State private var isWalking = false
    @State private var walkStart: Date?
    @State private var creditedBlocks = 0

    private let stepsPerBlock = 2000

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    walkCard
                    progressCard
                }
                .padding(18)
            }
        }
        .navigationTitle(environment.isEnglish ? "Outdoor" : "الخارج")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: motion.liveStepCount) { newValue in
            creditBlocksIfNeeded(steps: newValue)
        }
        .onDisappear {
            motion.stopLiveStepTracking()
        }
    }

    private var walkCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Meshwar Al-Sakeenah" : "مشوار السكينة",
                              subtitle: environment.isEnglish ? "2,000 steps per session." : "٢٠٠٠ خطوة لكل جلسة.")
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AATheme.glowGreenGradient)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(motion.liveStepCount)")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(AATheme.warmOffWhite)
                        Text(environment.isEnglish ? "steps" : "خطوة")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AATheme.mutedSilver)
                    }
                }
                if !motion.isPedometerAvailable {
                    Text(environment.isEnglish ? "Step counting is unavailable on this device." : "عدّ الخطوات غير متاح على هذا الجهاز.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.signalAmber)
                }
                PremiumButton(title: isWalking ? (environment.isEnglish ? "End Walk" : "إنهاء المشي") : (environment.isEnglish ? "Start Walk" : "ابدأ المشي"),
                              systemImage: isWalking ? "stop.fill" : "play.fill") {
                    toggleWalk()
                }
            }
        }
    }

    private var progressCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "This Week" : "هذا الأسبوع")
                Text(environment.isEnglish
                     ? "\(creditedBlocks) × 2,000-step blocks credited (+\(creditedBlocks * 25) PTS)."
                     : "تم احتساب \(creditedBlocks) × ٢٠٠٠ خطوة (+\(creditedBlocks * 25) نقطة).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(AATheme.warmOffWhite)
                ProgressRing(progress: min(1.0, Double(creditedBlocks) / 7.0), lineWidth: 8)
                    .frame(width: 70, height: 70)
            }
        }
    }

    private func toggleWalk() {
        isWalking.toggle()
        if isWalking {
            walkStart = Date()
            creditedBlocks = 0
            motion.startLiveStepTracking()
            haptics.tap()
        } else {
            motion.stopLiveStepTracking()
            haptics.success()
        }
    }

    private func creditBlocksIfNeeded(steps: Int) {
        guard isWalking else { return }
        let blocks = steps / stepsPerBlock
        if blocks > creditedBlocks {
            let newBlocks = blocks - creditedBlocks
            creditedBlocks = blocks
            environment.addPoints(newBlocks * 25, reason: "Meshwar Al-Sakeenah block", category: "outdoor")
            haptics.success()
        }
    }
}
