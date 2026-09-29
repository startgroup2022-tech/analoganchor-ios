import SwiftUI
import AnalogAnchorKit

/// Mosque / Sanctuary feature — prayer verification, Soft Landing and the
/// Maghrib-to-Isha retreat.
///
/// Location permission is requested only when the user asks to verify proximity
/// to a sanctuary (lazy, feature-triggered permission).
struct MosqueView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var haptics: HapticsService
    @EnvironmentObject private var mosque: MosqueLookupService

    @State private var retreatActive = false
    @State private var verificationMessage: String?

    /// Sanctuary default (Bahrain reference, mirrors Android default).
    private let sanctuary = (lat: LocationCodeParser.bahrainDefaultLat, lng: LocationCodeParser.bahrainDefaultLng)

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    locationCard
                    mosqueLookupCard
                    softLandingCard
                    retreatCard
                }
                .padding(18)
            }
        }
        .navigationTitle(L10n.text(.tabMosque, isEnglish: environment.isEnglish))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var locationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Sanctuary Presence" : "الحضور في المسجد")
                Text(environment.locationDescription)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(AATheme.warmOffWhite)
                if let verificationMessage {
                    Text(verificationMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.glowGreen)
                }
                PremiumButton(title: environment.isEnglish ? "Verify Proximity (+5 PTS)" : "تحقق من القرب (+٥ نقاط)", systemImage: "mappin.and.ellipse") {
                    Task { await verifyPresence() }
                }
            }
        }
    }

    private var softLandingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L10n.text(.softLanding, isEnglish: environment.isEnglish),
                              subtitle: environment.isEnglish ? "5 minutes before Dhuhr, Asr and Maghrib." : "خمس دقائق قبل الظهر والعصر والمغرب.")
                Text(environment.isEnglish
                     ? "On iOS, Soft Landing is delivered through Focus Filters and Time-Sensitive notifications. Schedule today's reminders:"
                     : "على iOS يُقدَّم الهبوط الناعم عبر مرشّحات التركيز والإشعارات الحساسة للوقت. جدولة تنبيهات اليوم:")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
                PremiumButton(title: environment.isEnglish ? "Schedule Today's Alerts" : "جدولة تنبيهات اليوم", systemImage: "bell.badge") {
                    Task {
                        await notifications.requestAuthorization()
                        if let times = environment.prayerTimes {
                            await notifications.schedulePrayerReminders(times, isEnglish: environment.isEnglish)
                            haptics.softLandingRhythm()
                        }
                    }
                }
            }
        }
    }

    private var retreatCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Maghrib-to-Isha Retreat" : "خلوة المغرب والعشاء",
                              subtitle: environment.isEnglish ? "Full digital isolation until Isha." : "عزل رقمي كامل حتى العشاء.")
                StatusPill(text: retreatActive ? (environment.isEnglish ? "RETREAT ACTIVE" : "الخلوة نشطة")
                                               : (environment.isEnglish ? "IDLE" : "غير نشطة"),
                           color: retreatActive ? AATheme.signalAmber : AATheme.mutedSilver)
                PremiumButton(title: retreatActive ? (environment.isEnglish ? "End Retreat (+40 PTS)" : "إنهاء الخلوة (+٤٠ نقطة)")
                                                   : (environment.isEnglish ? "Start Sacred Retreat" : "ابدأ الخلوة")) {
                    retreatActive.toggle()
                    haptics.softLandingRhythm()
                    environment.addPoints(retreatActive ? 0 : 40,
                                          reason: retreatActive ? "Retreat started" : "Retreat completed",
                                          category: "retreat")
                }
            }
        }
    }

    // MARK: - Nearby mosques (real Overpass lookup)

    private var mosqueLookupCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: environment.isEnglish ? "Nearby Sanctuaries" : "المساجد القريبة",
                    subtitle: environment.isEnglish ? "OpenStreetMap Overpass · 6 km" : "OpenStreetMap Overpass · ٦ كم"
                )
                if mosque.isSearching {
                    Text(environment.isEnglish ? "Searching…" : "جارٍ البحث…")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                } else if let error = mosque.lastError {
                    Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(AATheme.signalAmber)
                } else if mosque.candidates.isEmpty {
                    Text(environment.isEnglish ? "No results yet." : "لا توجد نتائج بعد.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                } else {
                    ForEach(mosque.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AATheme.warmOffWhite)
                            Text("\(candidate.distanceMeters) m · \(candidate.address)")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(AATheme.mutedSilver)
                        }
                    }
                }
                PremiumButton(title: environment.isEnglish ? "Find Nearby Mosques" : "ابحث عن مساجد قريبة", systemImage: "magnifyingglass") {
                    Task { await searchMosques() }
                }
            }
        }
    }

    /// Requests location lazily, then runs the same Overpass query Android uses.
    private func searchMosques() async {
        location.requestAuthorization()
        guard let current = await location.currentLocation() else {
            return
        }
        await mosque.search(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude)
    }

    private func verifyPresence() async {
        location.requestAuthorization()
        guard let current = await location.currentLocation() else {
            verificationMessage = environment.isEnglish
                ? "Location unavailable. Enable access to verify presence."
                : "الموقع غير متاح. فعّل الوصول للتحقق من الحضور."
            return
        }
        let metres = LocationService.distanceMeters(
            from: (current.coordinate.latitude, current.coordinate.longitude),
            to: sanctuary
        )
        environment.setLocationDescription(String(format: "%.4f, %.4f", current.coordinate.latitude, current.coordinate.longitude))
        environment.recalculatePrayerTimes()
        if metres <= 200 {
            verificationMessage = environment.isEnglish
                ? "Verified within \(Int(metres)) m. Presence confirmed."
                : "تم التحقق خلال \(Int(metres)) م. تم تأكيد الحضور."
            haptics.success()
            environment.addPoints(5, reason: "Sanctuary geofence verified", category: "mosque")
        } else {
            verificationMessage = environment.isEnglish
                ? "You are \(Int(metres)) m away (needs ≤ 200 m)."
                : "أنت على بُعد \(Int(metres)) م (المطلوب ≤ ٢٠٠ م)."
        }
    }
}
