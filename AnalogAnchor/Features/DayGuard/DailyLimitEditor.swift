import SwiftUI
import AnalogAnchorKit

/// Editor for a `.dailyLimit` rule. Produces a validated
/// `ScreenTimePolicy.Rule`; validation happens again in `ScreenTimeManager`.
struct DailyLimitEditor: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "Social"
    @State private var minutes: Int = AnalogAnchorConfig.defaultProtectedAppDailyLimitMinutes

    let onSave: (ScreenTimePolicy.Rule) -> Void

    private let presets = [15, 30, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section(environment.isEnglish ? "Name" : "الاسم") {
                    TextField(environment.isEnglish ? "Rule name" : "اسم القاعدة", text: $name)
                }
                Section(environment.isEnglish ? "Daily limit" : "الحد اليومي") {
                    Picker(environment.isEnglish ? "Minutes" : "الدقائق", selection: $minutes) {
                        ForEach(presets, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Stepper("\(minutes) min", value: $minutes, in: 1...(24 * 60), step: 5)
                }
            }
            .navigationTitle(environment.isEnglish ? "Daily Limit" : "حد يومي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(environment.isEnglish ? "Cancel" : "إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(environment.isEnglish ? "Save" : "حفظ") {
                        onSave(.init(kind: .dailyLimit, name: name, dailyLimitMinutes: minutes))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
