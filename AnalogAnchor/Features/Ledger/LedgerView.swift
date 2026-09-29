import SwiftUI
import AnalogAnchorKit

/// Ledger feature — weekly points economy, transaction history and the Friday
/// clean slate.
struct LedgerView: View {

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            AATheme.premiumBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    transactionList
                }
                .padding(18)
            }
        }
        .navigationTitle(L10n.text(.tabLedger, isEnglish: environment.isEnglish))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { environment.runWeeklyMaintenanceIfNeeded() }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: L10n.text(.reserveBalance, isEnglish: environment.isEnglish))
                        Text("\(environment.ledger.reservePoints) / \(Ledger.weeklyCeiling)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(AATheme.warmOffWhite)
                    }
                    Spacer()
                    ZStack {
                        ProgressRing(progress: environment.ledger.weeklyProgress, lineWidth: 10)
                            .frame(width: 84, height: 84)
                        Text("\(Int(environment.ledger.weeklyProgress * 100))%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AATheme.glowGreen)
                    }
                }
                HStack {
                    infoLine(environment.isEnglish ? "Banked stake" : "المخزون المرحّل", "\(environment.ledger.bankedStakePoints)")
                    Spacer()
                    infoLine(L10n.text(.weeklyCeiling, isEnglish: environment.isEnglish), "\(Ledger.weeklyCeiling)")
                }
            }
        }
    }

    private var transactionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: environment.isEnglish ? "This Week" : "هذا الأسبوع")
            if environment.ledger.transactions.isEmpty {
                GlassCard {
                    Text(environment.isEnglish ? "No transactions yet. Complete a ritual or prayer check-in to earn points." : "لا توجد حركات بعد. أكمل طقسًا أو تحقق صلاة لكسب النقاط.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AATheme.mutedSilver)
                }
            } else {
                ForEach(environment.ledger.transactions.reversed()) { tx in
                    GlassCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tx.reason)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AATheme.warmOffWhite)
                                Text(tx.date, style: .date)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(AATheme.mutedSilver)
                            }
                            Spacer()
                            Text(tx.points >= 0 ? "+\(tx.points)" : "\(tx.points)")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(tx.points >= 0 ? AATheme.glowGreen : AATheme.signalRed)
                        }
                    }
                }
            }
        }
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(AATheme.mutedSilver)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(AATheme.warmOffWhite)
        }
    }
}
