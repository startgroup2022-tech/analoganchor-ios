import Foundation
import UserNotifications
import AnalogAnchorKit

/// Local notification scheduling via `UNUserNotificationCenter`.
///
/// Replaces the Android `AlarmManager` + `NotificationManager` stack with the
/// only officially supported iOS equivalent. Phase 2 wires the categories and a
/// scheduling helper; the actual prayer/Fajr alarm engine is refined in the
/// Screen Time phase (AlarmKit / Time-Sensitive notifications).
@MainActor
final class NotificationService: NSObject, ObservableObject {

    /// Interactive actions, mirroring the Android Soft Landing quick action.
    enum Category {
        static let softLanding = "AA_SOFT_LANDING"
        static let fajrAlarm = "AA_FAJR_ALARM"
        static let anchorRitual = "AA_ANCHOR_RITUAL"
    }

    enum Action {
        static let engageSoftLanding = "AA_ENGAGE_SOFT_LANDING"
        static let dismissFajr = "AA_DISMISS_FAJR"
    }

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    func configure() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let engage = UNNotificationAction(identifier: Action.engageSoftLanding, title: "Engage Soft Landing", options: [])
        let dismiss = UNNotificationAction(identifier: Action.dismissFajr, title: "Verify Wake", options: [.foreground])
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Category.softLanding, actions: [engage], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.fajrAlarm, actions: [dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.anchorRitual, actions: [], intentIdentifiers: [])
        ]
        center.setNotificationCategories(categories)
        await refreshAuthorizationStatus()
    }

    func requestAuthorization() async {
        // Standard alert/sound/badge authorization only. Critical alerts and
        // Time-Sensitive interruption levels require separate Apple approval and
        // are requested separately once the entitlement is present.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Schedules a local notification (used for prayer reminders / Fajr).
    func schedule(
        id: String,
        title: String,
        body: String,
        at date: Date,
        categoryIdentifier: String? = nil,
        timeSensitive: Bool = false
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryIdentifier { content.categoryIdentifier = categoryIdentifier }
        if timeSensitive, #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Schedules the five daily prayer reminders from a calculated set.
    func schedulePrayerReminders(_ times: PrayerTimesCalculator.PrayerTimes, isEnglish: Bool) async {
        let labels: [(String, Date, String)] = [
            ("fajr", times.fajr, L10n.text(.fajr, isEnglish: isEnglish)),
            ("dhuhr", times.dhuhr, L10n.text(.dhuhr, isEnglish: isEnglish)),
            ("asr", times.asr, L10n.text(.asr, isEnglish: isEnglish)),
            ("maghrib", times.maghrib, L10n.text(.maghrib, isEnglish: isEnglish)),
            ("isha", times.isha, L10n.text(.isha, isEnglish: isEnglish))
        ]
        for (key, date, name) in labels {
            await schedule(
                id: "prayer_\(key)",
                title: name,
                body: isEnglish ? "It is time for prayer." : "حان وقت الصلاة.",
                at: date,
                timeSensitive: true
            )
        }

        // Soft Landing: 5 minutes before only Dhuhr/Asr/Maghrib (Isha excluded).
        for (key, date) in [("dhuhr", times.dhuhr), ("asr", times.asr), ("maghrib", times.maghrib)] {
            guard Policies.softLandingPrayers.contains(key) else { continue }
            let lead = date.addingTimeInterval(-Double(AnalogAnchorConfig.softLandingLeadMinutes) * 60)
            await schedule(
                id: "soft_landing_\(key)",
                title: L10n.text(.softLanding, isEnglish: isEnglish),
                body: isEnglish ? "Five minutes to prayer. Prepare to step away." : "بقي خمس دقائق للصلاة. استعد للانصراف.",
                at: lead,
                categoryIdentifier: Category.softLanding,
                timeSensitive: true
            )
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Handles a category action (e.g. "Verify Wake" on the Fajr alarm).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case Action.dismissFajr:
            let identifier = response.notification.request.identifier
            Task { @MainActor in NotificationCenter.default.post(name: .aaFajrAlarmDismissed, object: identifier) }
        case Action.engageSoftLanding:
            let identifier = response.notification.request.identifier
            Task { @MainActor in NotificationCenter.default.post(name: .aaSoftLandingEngaged, object: identifier) }
        default:
            break
        }
    }
}

extension Notification.Name {
    /// Posted when the user taps "Verify Wake" on the Fajr alarm.
    static let aaFajrAlarmDismissed = Notification.Name("AA_FAJR_ALARM_DISMISSED")
    /// Posted when the user engages Soft Landing from its notification.
    static let aaSoftLandingEngaged = Notification.Name("AA_SOFT_LANDING_ENGAGED")
}
