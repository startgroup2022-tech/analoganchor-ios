import SwiftUI
import AnalogAnchorKit

/// Dashboard — the iOS analogue of the Android home tab: prayer status, weekly
/// ledger ring, the 3-up pillar metrics and the Day Guard status card.
///
/// Day Guard here reports *readiness only* (Screen Time authorization); no app
/// blocking is performed in Phase 2.
struct DashboardView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var notifications: NotificationService
    @State private var showingProtocol = false
    @State private var showingSurvival = false
    @State private var showingAccountability = false

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    ledgerCard
                    metricsGrid
                    dayGuardCard
                    prayerTimesCard
                    quickLinks
                }
                .padding(18)
            }
        }
        .navigationTitle(L10n.text(.dashboardTitle, isEnglish: environment.isEnglish))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { environment.setEnglish(!environment.isEnglish) } label: {
                    Text(environment.isEnglish ? "ع" : "EN")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AATheme.glowGreen)
                }
            }
        }
        .sheet(isPresented: $showingProtocol) { ProtocolView() }
        .sheet(isPresented: $showingSurvival) { SurvivalView() }
        .sheet(isPresented: $showingAccountability) { AccountabilityView() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(.appName, isEnglish: environment.isEnglish))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(AATheme.warmOffWhite)
            Text(L10n.text(.tagline, isEnglish: environment.isEnglish))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(AATheme.mutedSilver)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ledgerCard: some View {
        GlassCard {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(progress: environment.ledger.weeklyProgress, lineWidth: 9)
                        .frame(width: 92, height: 92)
                    VStack(spacing: 0) {
                        Text("\(environment.ledger.reservePoints)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(AATheme.warmOffWhite)
                        Text("/ \(Ledger.weeklyCeiling)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AATheme.mutedSilver)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: L10n.text(.reserveBalance, isEnglish: environment.isEnglish))
                    Text(environment.isEnglish ? "Weekly clean slate every Friday before Jumu'ah." : "تصفير أسبوعي كل جمعة قبل الجمعة.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                    if environment.ledger.dayGuardUnlockMilestoneReached {
                        StatusPill(text: environment.isEnglish ? "150+ PTS · DAY GUARD UNLOCK READY" : "١٥٠+ نقطة · جاهز", color: AATheme.signalAmber)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricsGrid: some View {
        HStack(spacing: 10) {
            MetricTile(label: L10n.text(.paperRitual, isEnglish: environment.isEnglish), value: "\(environment.streaks.current(.anchor))")
            MetricTile(label: L10n.text(.retreat, isEnglish: environment.isEnglish), value: "\(environment.streaks.current(.maghribRetreat))", accent: AATheme.signalAmber)
            MetricTile(label: L10n.text(.lastFajr, isEnglish: environment.isEnglish), value: "\(environment.streaks.current(.mosque))")
        }
    }

    private var dayGuardCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: L10n.text(.dayGuardStatus, isEnglish: environment.isEnglish))
                    Spacer()
                    StatusPill(text: dayGuardStateText, color: dayGuardStateColor)
                }
                Text(environment.isEnglish
                     ? "Real shielding, schedules and limits. Day Guard applies ManagedSettings shields through Apple's Screen Time engine."
                     : "حجب وجداول وحدود حقيقية. يطبّق Day Guard الدروع عبر محرّك وقت الشاشة من Apple.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)

                HStack(spacing: 10) {
                    Image(systemName: environment.isScreenTimeEntitlementAvailable ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(dayGuardStateColor)
                    Text(environment.isEnglish ? "Family Controls entitlement:" : "استحقاق Family Controls:")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AATheme.warmOffWhite)
                    Spacer()
                    Text(environment.isScreenTimeEntitlementAvailable ? (environment.isEnglish ? "present" : "متاح") : (environment.isEnglish ? "not configured" : "غير مُهيّأ"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(dayGuardStateColor)
                }
            }
        }
    }

    private var prayerTimesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Today's Prayer Times" : "أوقات الصلاة اليوم")
                if let times = environment.prayerTimes {
                    ForEach(times.ordered, id: \.name) { entry in
                        HStack {
                            Text(prayerLabel(entry.name))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AATheme.warmOffWhite)
                            Spacer()
                            Text(entry.time, style: .time)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(AATheme.glowGreen)
                        }
                        if entry.name != "Isha" {
                            Divider().overlay(AATheme.obsidianBorder)
                        }
                    }
                } else {
                    Text(environment.isEnglish ? "Calculating…" : "جارٍ الحساب…")
                        .foregroundStyle(AATheme.mutedSilver)
                }
            }
        }
    }

    private var quickLinks: some View {
        VStack(spacing: 10) {
            NavigationLink { MosqueView() } label: {
                quickLinkLabel(L10n.text(.tabMosque, isEnglish: environment.isEnglish), icon: "building.columns", tint: AATheme.glowGreen)
            }
            NavigationLink { DayGuardView() } label: {
                quickLinkLabel(L10n.text(.dayGuardStatus, isEnglish: environment.isEnglish), icon: "shield.lefthalf.filled", tint: AATheme.signalAmber)
            }
            NavigationLink { OutdoorView() } label: {
                quickLinkLabel(environment.isEnglish ? "Outdoor" : "الخارج", icon: "figure.walk", tint: AATheme.glowGreen)
            }
            NavigationLink { FajrView() } label: {
                quickLinkLabel(L10n.text(.fajr, isEnglish: environment.isEnglish), icon: "alarm", tint: AATheme.signalAmber)
            }
            NavigationLink { PartnerCircleView() } label: {
                quickLinkLabel(environment.isEnglish ? "Partner Circle" : "دائرة الرفيق", icon: "person.2.wave.2", tint: AATheme.glowGreen)
            }
            PremiumButton(title: L10n.text(.protocolTitle, isEnglish: environment.isEnglish), systemImage: "list.bullet.rectangle") { showingProtocol = true }
            HStack(spacing: 10) {
                PremiumButton(title: L10n.text(.survivalTitle, isEnglish: environment.isEnglish), systemImage: "lifepreserver") { showingSurvival = true }
                PremiumButton(title: L10n.text(.accountabilityTitle, isEnglish: environment.isEnglish), systemImage: "person.2") { showingAccountability = true }
            }
        }
    }

    private func quickLinkLabel(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint).frame(width: 26)
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(AATheme.warmOffWhite)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(AATheme.mutedSilver)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AATheme.deepPanel)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.25), lineWidth: 1)))
    }

    private func prayerLabel(_ name: String) -> String {
        switch name {
        case "Fajr": return L10n.text(.fajr, isEnglish: environment.isEnglish)
        case "Dhuhr": return L10n.text(.dhuhr, isEnglish: environment.isEnglish)
        case "Asr": return L10n.text(.asr, isEnglish: environment.isEnglish)
        case "Maghrib": return L10n.text(.maghrib, isEnglish: environment.isEnglish)
        case "Isha": return L10n.text(.isha, isEnglish: environment.isEnglish)
        default: return environment.isEnglish ? "Sunrise" : "الشروق"
        }
    }

    private var dayGuardStateText: String {
        switch environment.screenTimeStatus {
        case .approved: return environment.isEnglish ? "AUTHORIZED" : "مُصرّح"
        case .denied: return environment.isEnglish ? "DECLINED" : "مرفوض"
        case .notDetermined: return environment.isEnglish ? "NOT SET" : "غير مُحدد"
        case .unavailable: return environment.isEnglish ? "N/A" : "غير متاح"
        }
    }

    private var dayGuardStateColor: Color {
        switch environment.screenTimeStatus {
        case .approved: return AATheme.glowGreen
        case .denied: return AATheme.signalRed
        case .notDetermined: return AATheme.signalAmber
        case .unavailable: return AATheme.mutedSilver
        }
    }
}
