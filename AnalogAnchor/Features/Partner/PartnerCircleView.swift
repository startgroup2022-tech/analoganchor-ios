import SwiftUI
import AnalogAnchorKit

/// Partner Circle — nearby accountability discovery over BLE.
///
/// The transport is the real `PartnerBluetoothTransport` (CoreBluetooth); this
/// view only presents what the radio actually reports. Scanning and advertising
/// run while the sheet is open (foreground), which is when the user expects them.
struct PartnerCircleView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var transport: PartnerBluetoothTransport
    @EnvironmentObject private var haptics: HapticsService
    @Environment(\.dismiss) private var dismiss

    @State private var refreshTimer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                AATheme.premiumBackdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        radarCard
                        if let error = transport.lastError {
                            GlassCard {
                                Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(AATheme.signalAmber)
                            }
                        }
                        if transport.connectedPartner != nil || transport.connectionState == .sessionActive {
                            sessionCard
                        }
                        settlementCard
                    }
                    .padding(18)
                }
            }
            .navigationTitle(environment.isEnglish ? "Partner Circle" : "دائرة الرفيق")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(environment.isEnglish ? "Close" : "إغلاق") { dismiss() }
                }
            }
            .onAppear { start() }
            .onDisappear { stop() }
        }
    }

    private var radarCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: environment.isEnglish ? "Nearby Partners" : "الرفقاء القريبون",
                              subtitle: environment.isEnglish ? "Bluetooth LE · while this screen is open" : "بلوتوث منخفض الطاقة · أثناء فتح الشاشة")
                HStack {
                    StatusPill(text: transport.isScanning ? (environment.isEnglish ? "SCANNING" : "يبحث") : (environment.isEnglish ? "IDLE" : "متوقف"),
                               color: transport.isScanning ? AATheme.glowGreen : AATheme.mutedSilver)
                    Spacer()
                    StatusPill(text: transport.isAdvertising ? (environment.isEnglish ? "VISIBLE" : "ظاهر") : (environment.isEnglish ? "HIDDEN" : "مخفي"),
                               color: transport.isAdvertising ? AATheme.glowGreen : AATheme.mutedSilver)
                }
                if transport.partners.isEmpty {
                    Text(environment.isEnglish
                         ? "No partners found yet. Ask your accountability partner to open this screen too."
                         : "لم يُعثر على رفقاء بعد. اطلب من رفيقك فتح هذه الشاشة أيضًا.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                } else {
                    ForEach(transport.partners) { partner in
                        partnerRow(partner)
                    }
                }
            }
        }
    }

    private func partnerRow(_ partner: DiscoveredPartner) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(AATheme.glowGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(partner.name).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(AATheme.warmOffWhite)
                Text(environment.isEnglish
                     ? "\(partner.rssi) dBm · \(partner.remainingMinutes) min"
                     : "\(partner.rssi) dBm · \(partner.remainingMinutes) دقيقة")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AATheme.mutedSilver)
            }
            Spacer()
            if partner.hasActiveSession {
                StatusPill(text: environment.isEnglish ? "IN SESSION" : "في جلسة", color: AATheme.signalAmber)
            }
            Button(environment.isEnglish ? "Connect" : "اتصال") {
                transport.connect(to: partner)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AATheme.glowGreen)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Session (real connect + domain settlement)

    private var sessionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Session" : "الجلسة")
                StatusPill(text: sessionStateText, color: sessionStateColor)
                if let partner = transport.connectedPartner {
                    Text(environment.isEnglish ? "Connected to \(partner.name)" : "متصل بـ \(partner.name)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AATheme.warmOffWhite)
                }
                HStack(spacing: 10) {
                    if transport.connectionState == .connected {
                        PremiumButton(title: environment.isEnglish ? "Start Session" : "ابدأ الجلسة", systemImage: "play.fill") {
                            transport.markSessionActive()
                            environment.beginPartnerSession(partnerName: transport.connectedPartner?.name ?? "Partner")
                            transport.advertisedHasActiveSession = true
                        }
                    }
                    if transport.connectionState == .sessionActive {
                        PremiumButton(title: environment.isEnglish ? "Complete" : "إتمام", systemImage: "checkmark") {
                            environment.settlePartnerCompletion(
                                isSuccess: true,
                                isGroup: false,
                                partnerName: transport.connectedPartner?.name ?? "Partner",
                                durationMinutes: PartnerDomain.defaultDurationMinutes
                            )
                            transport.markSessionCompleted()
                            transport.advertisedHasActiveSession = false
                        }
                    }
                    PremiumButton(title: environment.isEnglish ? "Disconnect" : "قطع الاتصال", systemImage: "xmark") {
                        if transport.connectionState == .sessionActive {
                            // Ending an active session early is a broken outing and
                            // settles through the domain, like Android.
                            environment.settlePartnerCompletion(
                                isSuccess: false,
                                isGroup: false,
                                partnerName: transport.connectedPartner?.name ?? "Partner",
                                durationMinutes: 0
                            )
                        }
                        transport.disconnect()
                        transport.advertisedHasActiveSession = false
                    }
                }
            }
        }
    }

    private var settlementCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Ledger Effect" : "الأثر في السجل")
                Text(environment.isEnglish
                     ? "Completion credits \(PartnerDomain.partnerCompletionPoints) PTS (solo) or \(PartnerDomain.groupCompletionPoints) PTS (group); an early exit or a never-activated covenant costs \(PartnerDomain.brokeCovenantPenalty) PTS."
                     : "الإتمام يمنح \(PartnerDomain.partnerCompletionPoints) نقطة (فردي) أو \(PartnerDomain.groupCompletionPoints) (جماعي)؛ والخروج المبكر أو عدم تفعيل الميثاق يكلّف \(PartnerDomain.brokeCovenantPenalty) نقطة.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
                if let session = environment.partnerSession {
                    Text(environment.isEnglish
                         ? "Pending session with \(session.partnerName) — activates within \(Int(PartnerDomain.pendingGraceWindow / 60)) min or it breaks the covenant."
                         : "جلسة معلّقة مع \(session.partnerName) — تُفعَّل خلال \(Int(PartnerDomain.pendingGraceWindow / 60)) دقيقة أو يُخرق الميثاق.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AATheme.signalAmber)
                }
            }
        }
    }

    private var sessionStateText: String {
        switch transport.connectionState {
        case .bluetoothUnavailable: return environment.isEnglish ? "BLUETOOTH OFF" : "البلوتوث متوقف"
        case .idle: return environment.isEnglish ? "IDLE" : "متوقف"
        case .scanning: return environment.isEnglish ? "SCANNING" : "يبحث"
        case .discovered: return environment.isEnglish ? "DISCOVERED" : "تم الاكتشاف"
        case .connecting: return environment.isEnglish ? "CONNECTING" : "جارٍ الاتصال"
        case .connected: return environment.isEnglish ? "CONNECTED" : "متصل"
        case .sessionActive: return environment.isEnglish ? "SESSION ACTIVE" : "الجلسة نشطة"
        case .completed: return environment.isEnglish ? "COMPLETED" : "مكتملة"
        case .cancelled: return environment.isEnglish ? "CANCELLED" : "ملغاة"
        case .timedOut: return environment.isEnglish ? "TIMED OUT" : "انتهت المهلة"
        }
    }

    private var sessionStateColor: Color {
        switch transport.connectionState {
        case .connected, .sessionActive, .completed: return AATheme.glowGreen
        case .connecting, .discovered, .scanning: return AATheme.signalAmber
        case .timedOut, .cancelled: return AATheme.signalRed
        default: return AATheme.mutedSilver
        }
    }

    private func start() {
        transport.advertisedName = environment.isEnglish ? "Analog Anchor" : "المرساة التناظرية"
        transport.advertisedHasActiveSession = environment.partnerSession != nil
        transport.advertisedRemainingMinutes = 60
        Task { await transport.startAdvertising() }
        transport.startScanning()
        // The radio prunes stale peers; mirror that on a short timer.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in transport.pruneStale() }
        }
    }

    private func stop() {
        refreshTimer?.invalidate()
        Task { await transport.stopAdvertising() }
        transport.stopScanning()
    }
}
