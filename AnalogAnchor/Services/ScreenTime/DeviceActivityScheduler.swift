import Foundation
import AnalogAnchorKit

#if canImport(DeviceActivity)
import DeviceActivity

#if canImport(FamilyControls)
import FamilyControls
#endif

/// Registers and reloads `DeviceActivity` schedules for the active policy.
///
/// ## What DeviceActivity can and cannot do
/// `DeviceActivitySchedule` + `DeviceActivityEvent` give us *interval* and
/// *usage-threshold* callbacks, delivered to a `DeviceActivityMonitor`
/// extension. They do **not** provide continuous, second-by-second usage
/// telemetry, and they cannot enumerate installed apps. Everything here is built
/// only on those two official primitives.
///
/// - A `.window` rule (bedtime / wind-down / Fajr lockdown) becomes one
///   `DeviceActivitySchedule`; the monitor shields on `intervalDidStart` and
///   clears on `intervalDidEnd`.
/// - A `.dailyLimit` rule becomes a `DeviceActivityEvent` threshold measured
///   against the shared selection; the monitor shields when the threshold is hit.
@MainActor
final class DeviceActivityScheduler {

    private let center = DeviceActivityCenter()

    enum SchedulerError: Error, LocalizedError {
        case invalidSchedule(String)
        case registrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidSchedule(let detail): return "Invalid schedule: \(detail)"
            case .registrationFailed(let detail): return "Could not register schedule: \(detail)"
            }
        }
    }

    /// Replaces all registered schedules with the ones implied by `policy`.
    ///
    /// Safe to call repeatedly; existing activities are stopped first so an
    /// edited policy never leaves a stale window behind.
    func reschedule(policy: ScreenTimePolicy, selection: ScreenTimeSelectionPayload) throws {
        center.stopMonitoring()

        guard policy.isEnabled else { return }

        for rule in policy.windowRules {
            guard let start = rule.startMinutes, let end = rule.endMinutes else { continue }

            // Always qualify every schedule with an explicit weekday. Apple
            // requires `intervalEnd` to come after `intervalStart`; expressing a
            // midnight-crossing window by the end landing on the *next* weekday
            // keeps that invariant true instead of relying on undefined
            // wrap-around behaviour for a bare hour/minute pair.
            let weekdays: [ScreenTimePolicy.Weekday] = rule.weekdays.isEmpty
                ? [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
                : rule.weekdays.sorted { $0.rawValue < $1.rawValue }

            for weekday in weekdays {
                var startComponents = DateComponents(hour: start / 60, minute: start % 60)
                var endComponents = DateComponents(hour: end / 60, minute: end % 60)
                startComponents.weekday = weekday.rawValue
                endComponents.weekday = rule.crossesMidnight
                    ? (weekday.rawValue % 7) + 1
                    : weekday.rawValue

                let schedule = DeviceActivitySchedule(
                    intervalStart: startComponents,
                    intervalEnd: endComponents,
                    repeats: true
                )
                let activity = DeviceActivityName(activityName(for: rule, weekday: weekday))
                do {
                    try center.startMonitoring(activity, during: schedule)
                } catch {
                    throw SchedulerError.registrationFailed("\(rule.name): \(error)")
                }
            }
        }

        // Daily limit threshold events, only if the user actually selected apps.
        if !selection.isEmpty, let event = dailyLimitEvent(for: policy, selection: selection) {
            do {
                try center.startMonitoring(
                    DeviceActivityName(AnalogAnchorConfig.deviceActivityName),
                    during: dailyMonitoringWindow(),
                    events: [DeviceActivityEvent.Name(AnalogAnchorConfig.dailyLimitEventName): event]
                )
            } catch {
                throw SchedulerError.registrationFailed("daily limit: \(error)")
            }
        }
    }

    /// Removes every Analog Anchor activity.
    func cancelAll() {
        center.stopMonitoring()
    }

    // MARK: - Naming

    private func activityName(for rule: ScreenTimePolicy.Rule, weekday: ScreenTimePolicy.Weekday) -> String {
        "\(AnalogAnchorConfig.deviceActivityName).window.\(rule.id.uuidString).\(weekday.rawValue)"
    }

    // MARK: - Events

    #if canImport(FamilyControls)
    private func dailyLimitEvent(
        for policy: ScreenTimePolicy,
        selection: ScreenTimeSelectionPayload
    ) -> DeviceActivityEvent? {
        let decoded = ScreenTimeSelectionCodec.decode(selection)
        guard !decoded.applicationTokens.isEmpty || !decoded.categoryTokens.isEmpty else { return nil }
        let minutes = policy.effectiveDailyLimitMinutes
        return DeviceActivityEvent(
            applications: decoded.applicationTokens,
            categories: decoded.categoryTokens,
            webDomains: decoded.webDomainTokens,
            threshold: DateComponents(minute: minutes)
        )
    }
    #else
    private func dailyLimitEvent(
        for policy: ScreenTimePolicy,
        selection: ScreenTimeSelectionPayload
    ) -> DeviceActivityEvent? { nil }
    #endif

    /// The monitoring interval for threshold events: a full day, starting at
    /// the next midnight boundary so the daily budget resets each day.
    func dailyMonitoringWindow() -> DeviceActivitySchedule {
        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }
}
#endif
