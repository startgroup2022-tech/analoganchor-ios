import SwiftUI
import AnalogAnchorKit

/// Root navigation for Analog Anchor (iOS).
///
/// Mirrors the Android hierarchy: a 3-item primary tab structure
/// (Dashboard / Anchor / Settings) with Protocol, Survival and Accountability
/// reachable from the dashboard — the same navigation model as the Android
/// `MainActivity` + `Screen` definitions.
struct RootView: View {

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if environment.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert("Setup note", isPresented: Binding(
            get: { environment.lastWarning != nil },
            set: { if !$0 { environment.lastWarning = nil } }
        )) {
            Button("OK", role: .cancel) { environment.lastWarning = nil }
        } message: {
            Text(environment.lastWarning ?? "")
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label(L10n.text(.tabDashboard, isEnglish: environment.isEnglish), systemImage: "house") }

            NavigationStack { AnchorRitualView() }
                .tabItem { Label(L10n.text(.tabAnchor, isEnglish: environment.isEnglish), systemImage: "scope") }

            NavigationStack { LedgerView() }
                .tabItem { Label(L10n.text(.tabLedger, isEnglish: environment.isEnglish), systemImage: "list.bullet.rectangle") }

            NavigationStack { SettingsView() }
                .tabItem { Label(L10n.text(.tabSettings, isEnglish: environment.isEnglish), systemImage: "gearshape") }
        }
        .tint(AATheme.glowGreen)
    }
}
