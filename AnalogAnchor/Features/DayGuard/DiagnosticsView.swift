import SwiftUI
import AnalogAnchorKit

/// Shows the cross-process diagnostics written by the app and its extensions.
/// Because extensions run in separate processes, failures there cannot surface
/// as thrown errors in the app — they land here instead.
struct DiagnosticsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let records: [DiagnosticRecord]
    let onClear: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if records.isEmpty {
                    Text(environment.isEnglish ? "No diagnostics recorded." : "لا توجد بيانات تشخيصية.")
                        .foregroundStyle(.secondary)
                }
                ForEach(records.reversed()) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.severity.rawValue.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(color(for: record.severity))
                            Text(record.source)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(record.date.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(record.message)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(environment.isEnglish ? "Diagnostics" : "التشخيص")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(environment.isEnglish ? "Close" : "إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(environment.isEnglish ? "Clear" : "مسح", role: .destructive) { onClear() }
                }
            }
        }
    }

    private func color(for severity: DiagnosticRecord.Severity) -> Color {
        switch severity {
        case .info: return AATheme.mutedSilver
        case .warning: return AATheme.signalAmber
        case .error: return .red
        }
    }
}
