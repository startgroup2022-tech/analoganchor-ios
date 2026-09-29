import SwiftUI
import AnalogAnchorKit

#if canImport(DeviceActivity)
import DeviceActivity
#endif

/// Hosts the `DeviceActivityReport` scene inside the app.
///
/// Rendering this view is what makes Apple run `AnalogAnchorDeviceActivityReport`;
/// the extension reduces the results to a `BehaviorReportSnapshot`, writes it to
/// the App Group, and `onRender` lets the app refresh its copy from there. The
/// app process can never read raw usage itself, so this render is the only data
/// path. Nothing is shown from this view directly — the numbers the user sees
/// come from the snapshot via `BehaviorReportProvider`.
///
/// When the report framework is absent (non-Apple build) the view renders an
/// honest "unavailable" state rather than any placeholder numbers.
struct UsageReportSceneView: View {

    /// Called once the report scene has rendered (i.e. the extension has run and
    /// had the chance to write the snapshot).
    var onRender: () -> Void = {}

    var body: some View {
        #if canImport(DeviceActivity)
        DeviceActivityReport(
            DeviceActivityReport.Context(BehaviorReportFilter.contextName),
            filter: BehaviorReportFilter.today()
        )
        .frame(minHeight: 90)
        .onAppear(perform: onRender)
        #else
        Text("Behavior data unavailable")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(AATheme.mutedSilver)
        #endif
    }
}
