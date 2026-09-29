import SwiftUI
import AnalogAnchorKit

/// Settings — mirrors the Android settings categories (General, Appearance,
/// Features, Data Management, About) with the language toggle and the Screen
/// Time readiness section.
struct SettingsView: View {

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            List {
                languageSection
                screenTimeSection
                generalSection
                appearanceSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L10n.text(.settings, isEnglish: environment.isEnglish))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var languageSection: some View {
        Section {
            Picker(L10n.text(.language, isEnglish: environment.isEnglish), selection: Binding(
                get: { environment.isEnglish },
                set: { environment.setEnglish($0) }
            )) {
                Text("English").tag(true)
                Text("العربية").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowBackground(AATheme.deepPanel)
        } header: {
            Text(L10n.text(.language, isEnglish: environment.isEnglish))
        }
    }

    private var screenTimeSection: some View {
        Section {
            HStack {
                Label(environment.isEnglish ? "Family Controls entitlement" : "استحقاق Family Controls", systemImage: "checkmark.shield")
                Spacer()
                Text(environment.isScreenTimeEntitlementAvailable ? "Present" : "Not configured")
                    .foregroundStyle(environment.isScreenTimeEntitlementAvailable ? AATheme.glowGreen : AATheme.signalAmber)
            }
            HStack {
                Label(environment.isEnglish ? "Authorization" : "التصريح", systemImage: "lock.shield")
                Spacer()
                Text(environment.screenTimeStatus.rawValue)
                    .foregroundStyle(AATheme.mutedSilver)
            }
            Button {
                Task { await environment.requestScreenTimeAuthorization() }
            } label: {
                Label(environment.isEnglish ? "Request Screen Time access" : "طلب الوصول لوقت الشاشة", systemImage: "hand.raised")
            }
            Text(environment.isEnglish
                 ? "Shields, DeviceActivity schedules and daily limits are active. Open Day Guard to configure them."
                 : "الدروع وجداول النشاط والحدود اليومية مفعّلة. افتح Day Guard لضبطها.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(AATheme.mutedSilver)
        } header: {
            Text(L10n.text(.dayGuardStatus, isEnglish: environment.isEnglish))
        }
        .listRowBackground(AATheme.deepPanel)
    }

    private var generalSection: some View {
        Section {
            HStack { Label(L10n.text(.general, isEnglish: environment.isEnglish), systemImage: "slider.horizontal.3"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(AATheme.mutedSilver) }
            HStack { Label(L10n.text(.features, isEnglish: environment.isEnglish), systemImage: "sparkles"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(AATheme.mutedSilver) }
        } header: {
            Text(L10n.text(.general, isEnglish: environment.isEnglish))
        }
        .listRowBackground(AATheme.deepPanel)
    }

    private var appearanceSection: some View {
        Section {
            HStack { Label(L10n.text(.appearance, isEnglish: environment.isEnglish), systemImage: "paintpalette"); Spacer(); Text("Obsidian / Glow").foregroundStyle(AATheme.mutedSilver) }
        } header: {
            Text(L10n.text(.appearance, isEnglish: environment.isEnglish))
        }
        .listRowBackground(AATheme.deepPanel)
    }

    private var dataSection: some View {
        Section {
            HStack { Label(L10n.text(.dataManagement, isEnglish: environment.isEnglish), systemImage: "externaldrive"); Spacer(); Text(SharedStore.isAppGroupAvailable() ? "App Group" : "Local").foregroundStyle(AATheme.mutedSilver) }
            HStack { Label(L10n.text(.protocolTitle, isEnglish: environment.isEnglish), systemImage: "list.bullet.rectangle") }
        } header: {
            Text(L10n.text(.dataManagement, isEnglish: environment.isEnglish))
        }
        .listRowBackground(AATheme.deepPanel)
    }

    private var aboutSection: some View {
        Section {
            HStack { Label(L10n.text(.about, isEnglish: environment.isEnglish), systemImage: "info.circle"); Spacer(); Text("iOS 2.8.7").foregroundStyle(AATheme.mutedSilver) }
            Link(destination: AnalogAnchorConfig.survivalKitURL) {
                Label(environment.isEnglish ? "Survival Kit (web)" : "عدة النجاة (ويب)", systemImage: "safari")
            }
        } header: {
            Text(L10n.text(.about, isEnglish: environment.isEnglish))
        }
        .listRowBackground(AATheme.deepPanel)
    }
}
