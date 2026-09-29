import SwiftUI
import AnalogAnchorKit

/// Anchor Ritual — the "Thinking on Paper" focus flow.
///
/// Reproduces the Android ritual: pick a duration, complete the physical
/// pre-flight checklist, then validate presence via an NFC tap. Motion
/// (face-down) monitoring is wired through `MotionService`.
struct AnchorRitualView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var nfc: NFCService
    @EnvironmentObject private var motion: MotionService
    @EnvironmentObject private var haptics: HapticsService

    @State private var selectedDuration = 5
    @State private var checklistDone = false
    @State private var sessionActive = false
    @State private var remainingSeconds = 0
    @State private var timer: Timer?
    @State private var errorMessage: String?

    /// Durations offered by Android's Protocol screen (`listOf(5, 10, 15)`).
    private let durations = AnchorRitual.offeredDurations

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    SectionHeader(title: L10n.text(.anchorRitual, isEnglish: environment.isEnglish),
                                  subtitle: environment.isEnglish ? "Analog deep work, validated by a physical tap." : "عمل عميق مادي، مؤكد بلمسة حقيقية.")
                    durationPicker
                    checklistCard
                    nfcCard
                    sessionCard
                }
                .padding(18)
            }
        }
        .navigationTitle(L10n.text(.anchorRitual, isEnglish: environment.isEnglish))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nfc.onTagScanned = handleTag }
        .onChange(of: motion.isFaceDown) { _, value in
            // The derived face-down decision flows into the domain, which owns the
            // pickup debounce + counting rule (`recordFocusPickup`).
            environment.updateRitualOrientation(isFaceDown: value)
        }
        .onDisappear { timer?.invalidate(); motion.stopFaceDownMonitoring() }
    }

    private var durationPicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: environment.isEnglish ? "Session Length" : "مدة الجلسة")
                HStack(spacing: 10) {
                    ForEach(durations, id: \.self) { d in
                        Button {
                            selectedDuration = d
                        } label: {
                            Text("\(d)m")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedDuration == d ? AnyShapeStyle(AATheme.glowGreenGradient) : AnyShapeStyle(AATheme.deepPanel)))
                                .foregroundStyle(selectedDuration == d ? AATheme.obsidianBg : AATheme.warmOffWhite)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var checklistCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: environment.isEnglish ? "Pre-Flight Checklist" : "قائمة ما قبل البدء")
                checklistRow(environment.isEnglish ? "Analog whiteboard open" : "اللوح الأبيض مفتوح", isOn: checklistDone)
                checklistRow(environment.isEnglish ? "Physical pen un-capped" : "القلم جاهز", isOn: checklistDone)
                checklistRow(environment.isEnglish ? "Phone positioned face-down" : "الهاتف مقلوب على وجهه", isOn: checklistDone)

                Button {
                    checklistDone = true
                    haptics.tap()
                } label: {
                    Text(checklistDone ? (environment.isEnglish ? "Checklist complete ✓" : "اكتملت القائمة ✓")
                                       : (environment.isEnglish ? "Confirm physical readiness" : "تأكيد الجاهزية الفيزيائية"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(checklistDone ? AATheme.glowGreen : AATheme.mutedSilver)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nfcCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Tap 1 — Desk Anchor" : "اللمسة ١ — مرساة المكتب")
                Text(environment.isEnglish
                     ? "Touch the top of your iPhone to the desk Anchor tag to start. Physical presence is required."
                     : "المس أعلى الآيفون بوسم المرساة على المكتب للبدء. الحضور الفيزيائي مطلوب.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
                if let error = nfc.lastError {
                    Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(AATheme.signalRed)
                }
                PremiumButton(
                    title: nfc.isScanning ? (environment.isEnglish ? "Scanning…" : "جارٍ المسح…") : (environment.isEnglish ? "Scan Anchor Tag" : "امسح وسم المرساة"),
                    systemImage: "wave.3.right",
                    isEnabled: checklistDone && !sessionActive
                ) {
                    nfc.beginScanning()
                }
                if !environment.isScreenTimeEntitlementAvailable {
                    Text(environment.isEnglish
                         ? "Note: NFC entitlement must be enabled in the signing profile."
                         : "ملاحظة: يجب تفعيل استحقاق NFC في ملف التوقيع.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AATheme.signalAmber)
                }
            }
        }
    }

    private var sessionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Session" : "الجلسة")
                if sessionActive {
                    Text(formatted(remainingSeconds))
                        .font(.system(size: 44, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AATheme.glowGreen)
                    StatusPill(text: motion.isFaceDown ? (environment.isEnglish ? "FACE-DOWN ✓" : "مقلوب ✓")
                                                       : (environment.isEnglish ? "PICKED UP" : "مُلتقط"),
                               color: motion.isFaceDown ? AATheme.glowGreen : AATheme.signalAmber)
                } else {
                    Text(environment.isEnglish ? "No active session. Tap the Anchor tag to begin." : "لا توجد جلسة. امسح وسم المرساة للبدء.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.signalAmber)
                }
            }
        }
    }

    private func checklistRow(_ title: String, isOn: Bool) -> some View {
        HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? AATheme.glowGreen : AATheme.mutedSilver)
            Text(title).font(.system(size: 13, design: .rounded)).foregroundStyle(AATheme.warmOffWhite)
            Spacer()
        }
    }

    private func handleTag(_ id: String, _ mime: String?) {
        // A physical tag was read: start the session through the domain, which
        // enforces the Android daily caps and owns the reward table.
        do {
            try environment.startRitual(durationMinutes: selectedDuration)
        } catch {
            errorMessage = environment.isEnglish
                ? "This session length is not available — a session already ran today."
                : "هذه المدة غير متاحة — أُنجزت جلسة اليوم بالفعل."
            haptics.error()
            return
        }
        errorMessage = nil
        remainingSeconds = environment.ritual.remainingSeconds
        sessionActive = true
        motion.startFaceDownMonitoring()
        haptics.tap()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if remainingSeconds > 0 {
                    remainingSeconds -= 1
                } else {
                    finishSession()
                }
            }
        }
    }

    private func finishSession() {
        timer?.invalidate()
        sessionActive = false
        motion.stopFaceDownMonitoring()
        haptics.success()
        // The domain computes the reward from the duration (25/35/45); the view
        // never invents points.
        try? environment.completeRitual()
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
