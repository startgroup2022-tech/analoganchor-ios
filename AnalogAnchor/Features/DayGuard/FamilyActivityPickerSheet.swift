import SwiftUI
import AnalogAnchorKit

#if canImport(FamilyControls)
import FamilyControls
#endif

/// Wraps Apple's `FamilyActivityPicker` so the user chooses applications,
/// categories and (optionally) web domains without the app ever enumerating
/// installed apps.
///
/// The chosen tokens are serialized by `ScreenTimeSelectionCodec` and handed to
/// `ScreenTimeManager.updateSelection` for App-Group storage.
struct FamilyActivityPickerSheet: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    #if canImport(FamilyControls)
    @State private var selection = FamilyActivitySelection()
    #endif

    var body: some View {
        NavigationStack {
            Group {
                #if canImport(FamilyControls)
                FamilyActivityPicker(selection: $selection)
                    .scrollContentBackground(.hidden)
                #else
                unavailablePlaceholder
                #endif
            }
            .background(AATheme.premiumBackdrop.ignoresSafeArea())
            .navigationTitle(environment.isEnglish ? "Choose Apps" : "اختر التطبيقات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(environment.isEnglish ? "Cancel" : "إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(environment.isEnglish ? "Save" : "حفظ") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var canSave: Bool {
        #if canImport(FamilyControls)
        return !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
        #else
        return false
        #endif
    }

    private func loadExisting() {
        #if canImport(FamilyControls)
        // Restore a previous selection so edits are cumulative, not a reset.
        let decoded = ScreenTimeSelectionCodec.decode(environment.screenTimeManager.selection)
        selection.applicationTokens = decoded.applicationTokens
        selection.categoryTokens = decoded.categoryTokens
        selection.webDomainTokens = decoded.webDomainTokens
        #endif
    }

    private func save() {
        #if canImport(FamilyControls)
        environment.screenTimeManager.updateSelection(ScreenTimeSelectionCodec.encode(selection))
        #endif
    }

    private var unavailablePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 36))
                .foregroundStyle(AATheme.signalAmber)
            Text(environment.isEnglish
                 ? "Family Controls is unavailable in this build."
                 : "ميزة Family Controls غير متاحة في هذه النسخة.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AATheme.warmOffWhite)
                .multilineTextAlignment(.center)
            Text(environment.isEnglish
                 ? "App selection requires an Apple Developer account with the Family Controls capability approved."
                 : "يتطلب اختيار التطبيقات حساب مطوّر Apple مع اعتماد قدرة Family Controls.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AATheme.mutedSilver)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}
