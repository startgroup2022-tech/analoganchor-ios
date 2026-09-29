import Foundation

/// Canonical, cross-platform configuration for Analog Anchor (iOS).
///
/// Every shared identifier lives here so the app, future extensions and the
/// web token tools agree on a single source of truth. These values mirror the
/// Android manifest / Gradle namespace (`com.analoganchor.app`) exactly.
public enum AnalogAnchorConfig {

    /// Root bundle / application identifier (matches Android namespace).
    public static let bundleIdentifier = "com.analoganchor.app"

    /// App Group used to share SwiftData + preferences with future extensions.
    public static let appGroupIdentifier = "group.com.analoganchor.app"

    // MARK: - NFC tag MIME types (mirror MainActivity.MIME_ANCHOR / MIME_FAJR)

    /// Main Anchor tag: routes to the Day Guard / Anchor ritual flow.
    public static let anchorTagMIMEType = "application/vnd.com.analoganchor.app.anchor"

    /// Fajr Eraser tag: routes to the Fajr lockdown confirmation.
    public static let fajrTagMIMEType = "application/vnd.com.analoganchor.app.fajr"

    // MARK: - Custom URL scheme (deep links / emergency tools)

    public static let urlScheme = "analoganchor"

    /// Canonical deep-link host names as `analoganchor://<host>`.
    public enum DeepLink {
        public static let anchor = "analoganchor://anchor"
        public static let fajr = "analoganchor://fajr"
        public static let survival = "analoganchor://survival"
        public static let emergency = "analoganchor://emergency"
    }

    // MARK: - Web-facing tools (remain outside the app, opened in Safari)

    public static let survivalKitURL = URL(string: "https://get-analog-anchor.com/survivalkit")!
    public static let supportToolURL = URL(string: "https://get-analog-anchor.com/support")!

    // MARK: - Numeric invariants (mirror AnchorViewModel companion constants)

    /// Weeks roll over on Friday morning before Jumu'ah.
    public static let weeklyLedgerResetWeekday = 6 // 1 = Sunday ... 7 = Saturday

    /// Soft Landing pre-Adhan window (minutes). Replaced the old 15m prayer buffer.
    public static let softLandingLeadMinutes = 5

    /// Default strict daily ceiling per protected app (minutes).
    public static let defaultProtectedAppDailyLimitMinutes = 60

    /// Partner "Circle" BLE service UUID — identical to Android's
    /// `PartnerPairingManager.SERVICE_UUID` so the two platforms can pair.
    public static let partnerServiceUUID = "0000AA01-0000-1000-8000-00805F9B34FB"

    /// Maximum partner-display-name bytes advertised (mirrors Android's cap).
    public static let partnerAdvertisedNameBytes = 11

    /// Fajr wake movement goal (steps across the room) after alarm dismissal.
    public static let fajrWakeStepGoal = 2

    // MARK: - Screen Time engine identifiers (Phase 3)

    /// `DeviceActivity` activity name used for every schedule we register.
    /// One name keeps `DeviceActivityCenter` bookkeeping simple; the concrete
    /// rule is resolved from the shared policy file inside the monitor.
    public static let deviceActivityName = "com.analoganchor.app.activity"

    /// `DeviceActivityEvent` name for the daily ceiling threshold.
    public static let dailyLimitEventName = "com.analoganchor.app.event.dailyLimit"

    /// Shared `ManagedSettingsStore` name.
    ///
    /// The app and every extension MUST use this same name: ManagedSettings
    /// stores are shared across the app group, so two different names would mean
    /// the app and the monitor shield/clear different stores and never agree.
    public static let managedSettingsStoreName = "analog-anchor.primary"

    /// App Group file names shared between the app and its extensions.
    ///
    /// Single source of truth: `SharedPolicyStore.Keys` aliases these values, so
    /// the app and every extension always resolve the same file in the shared
    /// container. Do not duplicate these strings elsewhere.
    public enum SharedFileNames {
        public static let policy = "screen-time-policy.json"
        public static let selection = "screen-time-selection.json"
        public static let diagnostics = "screen-time-diagnostics.json"
        public static let engineState = "screen-time-engine-state.json"
        /// Written by the DeviceActivityReport extension, read by the app.
        public static let behaviorReport = "behavior-report-snapshot.json"
    }
}
