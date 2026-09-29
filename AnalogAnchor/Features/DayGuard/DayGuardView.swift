import SwiftUI
import AnalogAnchorKit

/// Day Guard — the real digital-access control surface.
///
/// Every control here drives the live Screen Time engine via
/// `ScreenTimeManager` (policy) and `ScreenTimeCoordinator` (authorization):
/// app selection opens the real `FamilyActivityPicker`, the activate toggle
/// registers `DeviceActivity` schedules and applies `ManagedSettings` shields,
/// and unsupported states are shown honestly rather than as dead buttons.
struct DayGuardView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        DayGuardContent(manager: environment.screenTimeManager)
    }
}

private struct DayGuardContent: View {

    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var manager: ScreenTimeManager

    @State private var showingPicker = false
    @State private var showingLimitEditor = false
    @State private var showingWindowEditor = false
    @State private var showingDiagnostics = false

    init(manager: ScreenTimeManager) {
        self.manager = manager
    }

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    authorizationCard
                    engineCard
                    selectionCard
                    rulesCard
                    behaviorCard
                    if let error = manager.lastError { errorCard(error) }
                }
                .padding(18)
            }
        }
        .navigationTitle(L10n.text(.dayGuardStatus, isEnglish: environment.isEnglish))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            FamilyActivityPickerSheet().environmentObject(environment)
        }
        .sheet(isPresented: $showingLimitEditor) {
            DailyLimitEditor { rule in
                _ = manager.addRule(rule)
            }
            .environmentObject(environment)
        }
        .sheet(isPresented: $showingWindowEditor) {
            WindowEditor { rule in
                _ = manager.addRule(rule)
            }
            .environmentObject(environment)
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(records: manager.diagnostics) { manager.clearDiagnostics() }
                .environmentObject(environment)
        }
        .task {
            await environment.refreshScreenTimeState()
            environment.refreshBehaviorSnapshot()
        }
    }

    // MARK: - Authorization

    private var authorizationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Screen Time Authorization" : "تصريح وقت الشاشة")
                HStack(spacing: 10) {
                    Image(systemName: authorizationIcon)
                        .foregroundStyle(authorizationColor)
                    Text(authorizationText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AATheme.warmOffWhite)
                    Spacer()
                }
                if environment.screenTimeStatus != .approved {
                    PremiumButton(
                        title: environment.isEnglish ? "Authorize Screen Time" : "تفعيل تصريح وقت الشاشة",
                        systemImage: "checkmark.shield"
                    ) {
                        Task { await environment.requestScreenTimeAuthorization() }
                    }
                }
            }
        }
    }

    private var authorizationIcon: String {
        switch environment.screenTimeStatus {
        case .approved: return "checkmark.shield.fill"
        case .denied: return "xmark.shield.fill"
        case .notDetermined: return "questionmark.circle"
        case .unavailable: return "exclamationmark.shield.fill"
        }
    }

    private var authorizationColor: Color {
        switch environment.screenTimeStatus {
        case .approved: return AATheme.glowGreen
        case .denied, .unavailable: return AATheme.signalAmber
        case .notDetermined: return AATheme.mutedSilver
        }
    }

    private var authorizationText: String {
        switch environment.screenTimeStatus {
        case .approved:
            return environment.isEnglish ? "Authorized — shields can be applied." : "مصرّح — يمكن تطبيق الحجب."
        case .denied:
            return environment.isEnglish ? "Denied — enable Screen Time access in Settings." : "مرفوض — فعّل الوصول من الإعدادات."
        case .notDetermined:
            return environment.isEnglish ? "Not requested yet." : "لم يُطلب بعد."
        case .unavailable:
            return environment.isEnglish
                ? "Unavailable — Family Controls capability missing from this build."
                : "غير متاح — قدرة Family Controls غير موجودة في هذه النسخة."
        }
    }

    // MARK: - Engine

    private var engineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: environment.isEnglish ? "Day Guard Engine" : "محرّك Day Guard",
                                  subtitle: environment.isEnglish ? "Real shielding + schedules." : "حجب وجداول حقيقية.")
                    Spacer()
                    StatusPill(text: manager.isEngineActive ? (environment.isEnglish ? "ACTIVE" : "نشط") : (environment.isEnglish ? "OFF" : "متوقف"),
                               color: manager.isEngineActive ? AATheme.glowGreen : AATheme.mutedSilver)
                }
                Toggle(isOn: Binding(
                    get: { manager.isEngineActive },
                    set: { _ = manager.setEngineActive($0) }
                )) {
                    Text(environment.isEnglish ? "Active" : "مُفعّل")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AATheme.warmOffWhite)
                }
                .tint(AATheme.glowGreen)
                .disabled(environment.screenTimeStatus != .approved)

                if environment.screenTimeStatus != .approved {
                    Text(environment.isEnglish
                         ? "Authorize Screen Time above to enable the engine."
                         : "فعّل تصريح وقت الشاشة أعلاه لتشغيل المحرّك.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                }
            }
        }
    }

    // MARK: - Selection

    private var selectionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: environment.isEnglish ? "Protected Apps" : "التطبيقات المحمية",
                              subtitle: environment.isEnglish ? "Chosen with Apple's picker." : "تُختار عبر منتقي Apple.")
                HStack(spacing: 16) {
                    countBadge(value: manager.selection.applicationCount, label: environment.isEnglish ? "Apps" : "تطبيق")
                    countBadge(value: manager.selection.categoryCount, label: environment.isEnglish ? "Categories" : "فئة")
                    countBadge(value: manager.selection.webDomainCount, label: environment.isEnglish ? "Domains" : "نطاق")
                    Spacer()
                }
                PremiumButton(title: environment.isEnglish ? "Choose Apps" : "اختيار التطبيقات",
                              systemImage: "square.grid.2x2") {
                    showingPicker = true
                }
                .disabled(environment.screenTimeStatus != .approved)
            }
        }
    }

    private func countBadge(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(AATheme.glowGreen)
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(AATheme.mutedSilver)
        }
    }

    // MARK: - Rules

    private var rulesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: environment.isEnglish ? "Rules" : "القواعد",
                              subtitle: environment.isEnglish ? "Daily limits and blocked windows." : "حدود يومية ونوافذ حجب.")

                if manager.policy.rules.isEmpty {
                    Text(environment.isEnglish ? "No rules yet." : "لا توجد قواعد بعد.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                }

                ForEach(manager.policy.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AATheme.warmOffWhite)
                            Text(ruleDescription(rule))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AATheme.mutedSilver)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { manager.setRuleEnabled(id: rule.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        .tint(AATheme.glowGreen)

                        Button {
                            manager.removeRule(id: rule.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(AATheme.signalAmber)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    PremiumButton(title: environment.isEnglish ? "Add Limit" : "إضافة حد", systemImage: "timer") {
                        showingLimitEditor = true
                    }
                    PremiumButton(title: environment.isEnglish ? "Add Window" : "إضافة نافذة", systemImage: "moon.stars") {
                        showingWindowEditor = true
                    }
                }
                .disabled(environment.screenTimeStatus != .approved)
            }
        }
    }

    // MARK: - Behavior insights (real DeviceActivityReport data only)

    private var behaviorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: environment.isEnglish ? "Behavior Insights" : "رؤى السلوك",
                    subtitle: environment.isEnglish
                        ? "From Apple's DeviceActivity report — durations only."
                        : "من تقرير DeviceActivity — المدد فقط."
                )

                if !environment.isBehaviorMetricsAvailable {
                    // Honest empty state: no report yet, or Screen Time not authorized.
                    Text(environment.isEnglish ? "Behavior data unavailable" : "بيانات السلوك غير متاحة")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                    Text(environment.isEnglish
                         ? "Authorize Screen Time and render the report to populate this. Apple exposes aggregate durations only — no open counts."
                         : "فعّل وقت الشاشة واعرض التقرير لتعبئة هذا. توفّر Apple المدد المجمّعة فقط — دون عدد الفتحات.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                } else {
                    // Rendering this is what runs the extension; the numbers below
                    // are read back from the App Group snapshot it writes.
                    UsageReportSceneView { environment.refreshBehaviorSnapshot() }

                    if let snapshot = environment.behaviorSnapshot, !snapshot.applications.isEmpty {
                        Text(environment.isEnglish
                             ? "Window: last \(snapshot.windowHours)h · \(snapshot.applications.count) app(s)"
                             : "النافذة: آخر \(snapshot.windowHours) ساعة · \(snapshot.applications.count) تطبيق")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AATheme.mutedSilver)
                        ForEach(snapshot.applications, id: \.identifier) { app in
                            HStack {
                                Text(app.displayName ?? app.identifier)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AATheme.warmOffWhite)
                                Spacer()
                                Text("\(Int((app.totalSeconds / 60).rounded()))m")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AATheme.glowGreen)
                            }
                        }
                    } else {
                        Text(environment.isEnglish ? "No usage recorded in this window." : "لا يوجد استخدام مسجّل في هذه النافذة.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(AATheme.mutedSilver)
                    }

                    if environment.behaviorFlags.isEmpty {
                        Text(environment.isEnglish ? "No behavior flags raised." : "لم تُرفع أي رايات سلوكية.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(AATheme.mutedSilver)
                    } else {
                        ForEach(environment.behaviorFlags) { flag in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: flag.severity == .warn ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                    .foregroundStyle(flag.severity == .warn ? AATheme.signalAmber : AATheme.glowGreen)
                                Text(flag.message)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(AATheme.warmOffWhite)
                            }
                        }
                    }

                    PremiumButton(title: environment.isEnglish ? "Run Evaluation" : "تشغيل التقييم",
                                  systemImage: "arrow.triangle.2.circlepath") {
                        Task { await environment.runBehaviorEvaluation() }
                    }
                }
            }
        }
    }

    private func ruleDescription(_ rule: ScreenTimePolicy.Rule) -> String {
        switch rule.kind {
        case .dailyLimit:
            return "\(environment.isEnglish ? "Daily" : "يومي") · \(rule.dailyLimitMinutes ?? 0)m"
        case .window:
            let start = rule.startMinutes ?? 0
            let end = rule.endMinutes ?? 0
            let days = rule.weekdays.isEmpty
                ? (environment.isEnglish ? "Daily" : "يوميًا")
                : rule.weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.shortName).joined(separator: ",")
            return String(format: "%02d:%02d–%02d:%02d · %@", start / 60, start % 60, end / 60, end % 60, days)
        }
    }

    // MARK: - Errors

    private func errorCard(_ message: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AATheme.signalAmber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(environment.isEnglish ? "Screen Time error" : "خطأ في وقت الشاشة")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AATheme.warmOffWhite)
                    Text(message)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                    Button(environment.isEnglish ? "View diagnostics" : "عرض التشخيص") {
                        showingDiagnostics = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AATheme.glowGreen)
                }
            }
        }
    }
}
