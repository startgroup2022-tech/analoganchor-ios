import SwiftUI
import AnalogAnchorKit

/// Protocol — the first-request emergency bypass flow.
///
/// The real flow: request → 60-minute cooling window → token entry → shield
/// suspended for the active-unlock window → shield re-armed. Clearing and
/// re-arming the shield happen through `ScreenTimeManager` (ManagedSettings),
/// never from the view.
struct ProtocolView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var haptics: HapticsService
    @Environment(\.dismiss) private var dismiss

    @State private var tokenInput = ""
    @State private var statusMessage: String?
    @State private var coolingRemaining = 60 * 60
    @State private var coolingActive = false
    @State private var unlockActive = false
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                AATheme.premiumBackdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        coolingCard
                        tokenCard
                    }
                    .padding(18)
                }
            }
            .navigationTitle(L10n.text(.protocolTitle, isEnglish: environment.isEnglish))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(environment.isEnglish ? "Close" : "إغلاق") { dismiss() }
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var coolingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L10n.text(.coolingWindow, isEnglish: environment.isEnglish))
                Text(environment.isEnglish
                     ? "Requesting an unlock starts an irreversible 60-minute cooling period. No token can be generated before it reaches 00:00."
                     : "يبدأ طلب الفتح فترة تبريد غير قابلة للتراجع مدتها ٦٠ دقيقة. لا يمكن توليد رمز قبل وصولها إلى ٠٠:٠٠.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
                if coolingActive {
                    Text(formatted(coolingRemaining))
                        .font(.system(size: 40, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AATheme.signalAmber)
                }
                PremiumButton(
                    title: coolingActive ? (environment.isEnglish ? "Cooling…" : "جارٍ التبريد…") : (environment.isEnglish ? "Request Emergency Unlock" : "طلب الفتح الطارئ"),
                    systemImage: "hourglass",
                    isEnabled: !coolingActive
                ) {
                    startCooling()
                }
            }
        }
    }

    private var tokenCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Access Token" : "رمز الوصول",
                              subtitle: "AA-ANCHOR-…-EXP60")
                TextField(environment.isEnglish ? "Paste or type your token" : "الصق أو اكتب الرمز", text: $tokenInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AATheme.deepPanel))
                    .foregroundStyle(AATheme.warmOffWhite)
                    .onSubmit { authorize() }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(statusMessage.hasPrefix("✔") ? AATheme.glowGreen : AATheme.signalRed)
                }
                PremiumButton(title: environment.isEnglish ? "Authorize Token" : "تحقق من الرمز", systemImage: "key", isEnabled: !tokenInput.isEmpty) {
                    authorize()
                }
                Link(environment.isEnglish ? "Need a token? Open the survival kit." : "تحتاج رمزًا؟ افتح عدة النجاة.",
                     destination: AnalogAnchorConfig.survivalKitURL)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.glowGreen)
            }
        }
    }

    private func startCooling() {
        coolingActive = true
        coolingRemaining = 60 * 60
        haptics.tap()
        let cooldownStart = Date()
        environment.beginEmergencyCoolDown(now: cooldownStart)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if coolingRemaining > 0 { coolingRemaining -= 1 } else { timer?.invalidate() }
                environment.refreshEmergencyCoolDown(cooldownStart: cooldownStart)
            }
        }
    }

    private func authorize() {
        let normalized = TokenCodec.normalize(tokenInput)
        let isDecoy = TokenCodec.isDecoy(normalized)
        let pin = TokenCodec.decodedPin(from: normalized)

        // The decision + effect live in the domain/Screen Time layer; the view
        // only reports the outcome. A valid token suspends shields through the
        // adapter — never ManagedSettings from here.
        let result = environment.authorizeEmergencyToken(
            decodedSuccessfully: pin != nil || isDecoy,
            isDecoy: isDecoy
        )

        switch result.kind {
        case .decoy:
            statusMessage = environment.isEnglish
                ? "✔ Decoy token accepted — illusion armed."
                : "✔ تم قبول الرمز الوهمي."
            haptics.success()
        case .token:
            // Do NOT display the raw PIN in production UI; log acceptance only.
            statusMessage = environment.isEnglish
                ? "✔ Token valid (PIN length \(pin?.count ?? 0)). Shield suspended."
                : "✔ الرمز صالح (طول الرقم \(pin?.count ?? 0)). تم رفع الحجب."
            haptics.success()
            // The shield is now suspended; re-arm it when the active-unlock
            // window closes so a bypass is temporary, as on Android.
            if !unlockActive, let end = result.unlockedUntil {
                unlockActive = true
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    Task { @MainActor in
                        if Date() >= end {
                            timer?.invalidate()
                            unlockActive = false
                            environment.endEmergencyUnlock()
                        }
                    }
                }
            }
        case .rejected:
            statusMessage = environment.isEnglish
                ? "✘ Invalid or expired token."
                : "✘ رمز غير صالح أو منتهٍ."
            haptics.error()
        }
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
