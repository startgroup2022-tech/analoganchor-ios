import DeviceActivity
import SwiftUI
import AnalogAnchorKit

/// DeviceActivity Report extension.
///
/// ## What this extension is and is not
/// Apple allows *detailed* Screen Time usage only inside a report extension:
/// `DeviceActivityReport` hands the extension a `DeviceActivityResults` stream
/// that the app process can never read directly. This extension therefore:
///
/// 1. consumes the real `DeviceActivityResults` for the queried interval,
/// 2. reduces them to aggregate **durations** (the only per-app datum Apple
///    exposes — there are no open counts, no launch timestamps),
/// 3. writes the reduced snapshot to the shared App Group so the app's
///    `BehaviorMetricsProvider` can read it, and
/// 4. renders a SwiftUI summary using the same Obsidian/Glow identity.
///
/// It does **not** enumerate installed apps, invent open counts, or log any
/// identifier — nothing sensitive is printed.
///
/// Entry point is `@main` (the SwiftUI extension style). This extension point
/// does **not** accept `NSExtensionPrincipalClass` on iOS 18+, so the Info.plist
/// declares only the point identifier.
@main
struct DeviceActivityReportExtension: DeviceActivityReportExtension {

    var body: some DeviceActivityReportScene {
        // One scene: total per-application usage over the configured window.
        BehaviorUsageReport { configuration in
            BehaviorUsageView(configuration: configuration)
        }
    }
}

/// The report scene: turns `DeviceActivityResults<DeviceActivityData>` into the
/// portable `BehaviorReportSnapshot` and a small view configuration.
struct BehaviorUsageReport: DeviceActivityReportScene {

    /// The label Apple shows for this report.
    let context: DeviceActivityReport.Context = .init("Analog Anchor Usage")

    /// How long a window the report covers. Apple's own guidance is to keep
    /// report windows short; the app asks for the last 24 hours.
    let windowHours: Int = 24

    let content: (Configuration) -> BehaviorUsageView

    struct Configuration {
        var applications: [BehaviorReportSnapshot.AppUsage]
        var categories: [BehaviorReportSnapshot.CategoryUsage]
    }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Configuration {
        var applications: [BehaviorReportSnapshot.AppUsage] = []
        var categories: [BehaviorReportSnapshot.CategoryUsage] = []

        // `DeviceActivityData` is per-activity (application or category); each
        // carries `activitySegments` whose `totalActivityDuration` is the only
        // aggregate Apple exposes.
        for await activityData in data {
            var totalSeconds: TimeInterval = 0
            for await segment in activityData.activitySegments {
                totalSeconds += segment.totalActivityDuration
            }

            switch activityData.activity {
            case .application(let application):
                // The application's own bundle identifier is provided by the
                // framework for the *already-shielded* selection; we never ask
                // for a full installed-apps list.
                applications.append(.init(
                    identifier: application.bundleIdentifier ?? "application",
                    displayName: application.localizedDisplayName,
                    totalSeconds: totalSeconds
                ))
            case .category(let category):
                categories.append(.init(
                    identifier: category.localizedDisplayName ?? "category",
                    displayName: category.localizedDisplayName,
                    totalSeconds: totalSeconds
                ))
            case .webDomain(let domain):
                // Web domains are surfaced as categories-like entries; the app
                // only consumes application rows today.
                categories.append(.init(
                    identifier: domain.domain ?? "webDomain",
                    displayName: domain.domain,
                    totalSeconds: totalSeconds
                ))
            @unknown default:
                break
            }
        }

        // Persist the reduced snapshot for the main app. Failure is recorded as
        // a diagnostic rather than silently dropped.
        var store = SharedPolicyStore()
        let snapshot = BehaviorReportSnapshot(
            windowHours: windowHours,
            applications: applications,
            categories: categories
        )
        if store.saveBehaviorReport(snapshot) == false {
            store.appendDiagnostic(.init(
                severity: .warning,
                source: "report",
                message: "Could not write the behavior report snapshot to the App Group."
            ))
        }

        return Configuration(applications: applications, categories: categories)
    }
}

/// Minimal, privacy-safe summary view for the report scene.
struct BehaviorUsageView: View {

    let configuration: BehaviorUsageReport.Configuration

    private var totalMinutes: Int {
        Int((configuration.applications.reduce(0) { $0 + $1.totalSeconds } / 60).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANALOG ANCHOR")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.55))
            Text("\(totalMinutes) min tracked across \(configuration.applications.count) app(s)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Aggregate usage only — this report never lists your installed apps.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Color(white: 0.7))
        }
        .padding(12)
    }
}
