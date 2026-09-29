import SwiftUI
import AnalogAnchorKit

/// Accountability — the founder / trusted-contact custody view.
///
/// Reproduces the Android "external custody" concept: uninstall PIN state, the
/// trusted contact, and the audit trail of unlock requests. Token entry here is
/// the same decoder used by the Protocol screen.
struct AccountabilityView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var contactName = ""
    @State private var savedContact: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AATheme.premiumBackdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        custodyCard
                        auditCard
                    }
                    .padding(18)
                }
            }
            .navigationTitle(L10n.text(.accountabilityTitle, isEnglish: environment.isEnglish))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(environment.isEnglish ? "Close" : "إغلاق") { dismiss() }
                }
            }
            .onAppear {
                savedContact = PreferencesStore().string(.emergencyState)
            }
        }
    }

    private var custodyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Trusted Contact" : "جهة الوثوق")
                Text(environment.isEnglish
                     ? "On iOS the exit key is enforced by a private Screen Time passcode plus this trusted contact — no accessibility gestures."
                     : "على iOS يُفروض مفتاح الخروج عبر رمز وقت الشاشة الخاص وجهة الوثوق هذه — دون أي إيماءات وصول.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
                TextField(environment.isEnglish ? "Contact name" : "اسم جهة الوثوق", text: $contactName)
                    .font(.system(size: 14, design: .rounded))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AATheme.deepPanel))
                    .foregroundStyle(AATheme.warmOffWhite)
                PremiumButton(title: environment.isEnglish ? "Save Contact" : "حفظ", isEnabled: !contactName.isEmpty) {
                    PreferencesStore().set(contactName, for: .emergencyState)
                    savedContact = contactName
                }
                if let savedContact {
                    StatusPill(text: "\(environment.isEnglish ? "Custodian" : "المسؤول"): \(savedContact)", color: AATheme.glowGreen)
                }
            }
        }
    }

    private var auditCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: environment.isEnglish ? "Audit Trail" : "سجل التدقيق")
                Text(environment.isEnglish
                     ? "\(environment.ledger.transactions.count) ledger events recorded this week."
                     : "تم تسجيل \(environment.ledger.transactions.count) حدثًا في السجل هذا الأسبوع.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(AATheme.warmOffWhite)
                Text(environment.isEnglish
                     ? "Emergency bypass requires a 60-minute cooling window and a valid AA-ANCHOR token."
                     : "يتطلب التجاوز الطارئ نافذة تبريد ٦٠ دقيقة ورمز AA-ANCHOR صالحًا.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AATheme.mutedSilver)
            }
        }
    }
}
