import SwiftUI
import AnalogAnchorKit

/// Fajr / wake-proof screen.
///
/// Implements the two-step wake verification the Android app drives with an
/// AlarmManager foreground service: dismiss the alarm in-app, then prove you are
/// physically up either by moving across the room (CoreMotion steps) or by
/// tapping the Fajr eraser tag (CoreNFC). Points are credited by the domain via
/// `FajrService.onWakeProofEarned`.
struct FajrView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var fajr: FajrService
    @EnvironmentObject private var motion: MotionService
    @EnvironmentObject private var nfc: NFCService
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var haptics: HapticsService

    @State private var message: String?

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    alarmCard
                    wakeCard
                }
                .padding(18)
            }
        }
        .navigationTitle(L10n.text(.fajr, isEnglish: environment.isEnglish))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: motion.liveStepCount) { _, value in
            fajr.updateWakeSteps(cumulativeSteps: value)
        }
        .onAppear {
            fajr.reloadDailyState()
            nfc.onTagScanned = { tagID, _ in
                fajr.recordNFCTag(tagID)
                haptics.success()
            }
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Today's Fajr" : "فجر اليوم")
                StatusPill(
                    text: fajr.isFajrSatisfied
                        ? (environment.isEnglish ? "SATISFIED" : "مُحقّق")
                        : (environment.isEnglish ? "PENDING" : "قيد الانتظار"),
                    color: fajr.isFajrSatisfied ? AATheme.glowGreen : AATheme.signalAmber
                )
                if let message {
                    Text(message).font(.system(size: 12, design: .rounded)).foregroundStyle(AATheme.mutedSilver)
                }
                if let prayerTime = environment.prayerTimes?.fajr {
                    Text(environment.isEnglish
                         ? "Today's Fajr: \(prayerTime.formatted(date: .omitted, time: .shortened))"
                         : "فجر اليوم: \(prayerTime.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(AATheme.warmOffWhite)
                }
                if !fajr.isFajrSatisfied {
                    PremiumButton(title: environment.isEnglish ? "Verify Fajr Prayer" : "تأكيد صلاة الفجر", systemImage: "checkmark.seal") {
                        fajr.recordPrayerVerified()
                        haptics.success()
                    }
                }
            }
        }
    }

    private var alarmCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Wake Alarm" : "منبّه الاستيقاظ",
                              subtitle: environment.isEnglish ? "Time-sensitive notification" : "إشعار حساس للوقت")
                Text(environment.isEnglish
                     ? "iOS has no foreground alarm service, so Fajr is delivered as a time-sensitive notification. Dismiss it here to arm the wake proof."
                     : "لا توجد خدمة منبّه في الخلفية على iOS، لذا يُسلَّم الفجر كإشعار حساس للوقت. أزِله هنا لتنشيط إثبات الاستيقاظ.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
                PremiumButton(title: environment.isEnglish ? "Schedule Fajr Alarm" : "جدولة منبه الفجر", systemImage: "alarm") {
                    Task {
                        await notifications.requestAuthorization()
                        if let times = environment.prayerTimes {
                            await fajr.scheduleFajr(for: times, isEnglish: environment.isEnglish)
                            message = environment.isEnglish ? "Fajr alarm scheduled." : "تمت جدولة منبه الفجر."
                        }
                    }
                }
                PremiumButton(title: environment.isEnglish ? "I Dismissed It (arm wake proof)" : "أزلته (نشّط إثبات الاستيقاظ)", systemImage: "hand.raised") {
                    fajr.recordAlarmDismissed()
                    haptics.tap()
                }
            }
        }
    }

    private var wakeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Prove You're Awake" : "أثبت أنك مستيقظ",
                              subtitle: environment.isEnglish ? "Move \(AnalogAnchorConfig.fajrWakeStepGoal) steps or tap the tag" : "تحرك \(AnalogAnchorConfig.fajrWakeStepGoal) خطوات أو المس الوسم")
                HStack {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AATheme.glowGreenGradient)
                    Spacer()
                    Text("\(fajr.wakeTracker.stepsAfterDismiss)/\(AnalogAnchorConfig.fajrWakeStepGoal)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AATheme.warmOffWhite)
                }
                if !motion.isPedometerAvailable {
                    Text(environment.isEnglish ? "Step counting is unavailable on this device — use the NFC tag." : "عدّ الخطوات غير متاح — استخدم وسم NFC.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.signalAmber)
                }
                PremiumButton(title: environment.isEnglish ? "Tap Fajr Eraser Tag (NFC)" : "المس ممحاة الفجر (NFC)", systemImage: "wave.3.right") {
                    Task {
                        let tag = await nfc.scanTag()
                        if let tag, !tag.isEmpty {
                            fajr.recordNFCTag(tag)
                            haptics.success()
                        } else {
                            message = nfc.lastError ?? (environment.isEnglish ? "No tag read." : "لم يُقرأ وسم.")
                        }
                    }
                }
                if let event = fajr.lastWakeEvent {
                    Text(event).font(.system(size: 12, design: .rounded)).foregroundStyle(AATheme.glowGreen)
                }
            }
        }
    }
}
