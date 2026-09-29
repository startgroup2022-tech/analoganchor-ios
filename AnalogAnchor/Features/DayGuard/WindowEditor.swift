import SwiftUI
import AnalogAnchorKit

/// Editor for a `.window` rule (bedtime, wind-down, Fajr lockdown).
///
/// Cross-midnight windows are first-class: start > end is stored as-is and
/// evaluated by `ScreenTimePolicy.isBlockedByWindow`.
struct WindowEditor: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "Bedtime"
    @State private var start: Date = Self.time(22, 0)
    @State private var end: Date = Self.time(7, 0)
    @State private var weekdays: Set<ScreenTimePolicy.Weekday> = []

    let onSave: (ScreenTimePolicy.Rule) -> Void

    static func time(_ hour: Int, _ minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(environment.isEnglish ? "Name" : "الاسم") {
                    TextField(environment.isEnglish ? "Rule name" : "اسم القاعدة", text: $name)
                }
                Section(environment.isEnglish ? "Window" : "النافذة") {
                    DatePicker(environment.isEnglish ? "Start" : "البداية", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker(environment.isEnglish ? "End" : "النهاية", selection: $end, displayedComponents: .hourAndMinute)
                    if minutes(end) <= minutes(start) {
                        Text(environment.isEnglish
                             ? "This window crosses midnight (e.g. bedtime)."
                             : "هذه النافذة تعبر منتصف الليل (مثل وقت النوم).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section(environment.isEnglish ? "Days" : "الأيام") {
                    ForEach(ScreenTimePolicy.Weekday.allCases, id: \.self) { day in
                        Button {
                            if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                        } label: {
                            HStack {
                                Text(day.shortName)
                                Spacer()
                                if weekdays.contains(day) {
                                    Image(systemName: "checkmark").foregroundStyle(AATheme.glowGreen)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text(environment.isEnglish ? "No days selected = every day." : "بدون تحديد أيام = كل يوم.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(environment.isEnglish ? "Blocked Window" : "نافذة الحجب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(environment.isEnglish ? "Cancel" : "إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(environment.isEnglish ? "Save" : "حفظ") {
                        onSave(.init(
                            kind: .window,
                            name: name,
                            startMinutes: minutes(start),
                            endMinutes: minutes(end),
                            weekdays: weekdays
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
