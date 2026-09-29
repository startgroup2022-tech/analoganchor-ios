import Foundation

/// Lightweight, cross-process preferences stored in the shared App Group.
///
/// Mirrors the subset of Android `DataStore` values that are boolean/scalar
/// flags rather than records (onboarding, alarm toggles, theme, language...).
/// Records live in SwiftData; this store is for flags only — it is explicitly
/// NOT the primary database.
public final class PreferencesStore {

    private let defaults: UserDefaults

    public init(suiteName: String = AnalogAnchorConfig.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Typed accessors

    public func bool(_ key: Key, default defaultValue: Bool = false) -> Bool {
        defaults.object(forKey: key.rawValue) as? Bool ?? defaultValue
    }

    public func set(_ value: Bool, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    public func int(_ key: Key, default defaultValue: Int = 0) -> Int {
        defaults.object(forKey: key.rawValue) as? Int ?? defaultValue
    }

    public func set(_ value: Int, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    public func string(_ key: Key) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    public func set(_ value: String?, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    public func double(_ key: Key, default defaultValue: Double = 0) -> Double {
        defaults.object(forKey: key.rawValue) as? Double ?? defaultValue
    }

    public func set(_ value: Double, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    /// Keys mirror the Android preference names where they exist.
    public enum Key: String {
        case isOnboarded = "is_onboarded"
        case isEnglish = "is_english"
        case themeMode = "app_theme_mode"
        case compactness = "compactness_option"
        case fajrAlarmEnabled = "fajr_alarm_enabled"
        case fajrAlarmNFCUnlocked = "fajr_alarm_nfc_unlocked"
        case anchorNFCTagID = "anchor_nfc_tag_id"
        case fajrNFCTagID = "fajr_nfc_tag_id"
        case userLatitude = "user_lat"
        case userLongitude = "user_lng"
        case userLocationName = "user_location_name"
        case sanctuaryLatitude = "sanctuary_lat"
        case sanctuaryLongitude = "sanctuary_lng"
        case sanctuaryType = "sanctuary_type"
        case lastFridayResetDate = "last_friday_reset_date"
        case reservePoints = "reserve_points"
        case bankedStakePoints = "banked_stake_points"
        case emergencyState = "emergency_state"
        case emergencyRequestStart = "emergency_token_timestamp"
        case screenTimeAuthorizationStatus = "screen_time_authorization_status"
        case lastKnownDailyUsageMillis = "last_known_daily_usage"
        case lastKnownDailyUsageDate = "last_known_daily_usage_date"
        // Anchor Ritual daily counters (Android: daily_25m_count_<date>,
        // daily_long_session_<date>, daily_reflection_count_<date>). Scoped to a
        // calendar day via `ritualCountersDate`.
        case ritualCountersDate = "ritual_counters_date"
        case dailyShortSessionCount = "daily_25m_count"
        case dailyLongSession = "daily_long_session"
        case dailyReflectionCount = "daily_reflection_count"
        // Fajr daily proof state (Android: fajr_verified_<date>,
        // fajr_alarm_dismissed_<date>, fajr_wake_verified_<date>). Scoped to a
        // day via `fajrProofDate`.
        case fajrProofDate = "fajr_proof_date"
        case fajrAlarmDismissedInApp = "fajr_alarm_dismissed"
        case fajrWakeVerified = "fajr_wake_verified"
        case fajrPrayerVerified = "fajr_prayer_verified"
        case fajrMissed = "fajr_missed"
    }
}
