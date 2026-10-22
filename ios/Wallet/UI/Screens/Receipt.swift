import SwiftUI

/// The screen after a top-up or payment went through (hook "result"). No back button: the money has
/// moved, and the way on is Done. `replayed`: the API answered Idempotent-Replayed: true (SPEC K-06).
/// Same layout as the Android Receipt.kt; the rows fill a card padded 4 above and below (SPEC §7.7).
struct Receipt<Actions: View, Rows: View>: View {
    let title: String
    let heading: String
    let amount: String
    var replayed = false
    @ViewBuilder let actions: Actions
    @ViewBuilder let rows: Rows

    var body: some View {
        Screen(title: title) {
            actions
        } content: {
            VStack(alignment: .leading, spacing: WalletSpacing.lg) {
                HStack(spacing: WalletSpacing.sm) {
                    Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(WalletColors.amountCredit)
                        .frame(width: 24, height: 24).accessibilityHidden(true)
                    Text(heading).walletText(WalletType.titleLarge).foregroundStyle(WalletColors.textPrimary)
                }
                HStack(alignment: .firstTextBaseline, spacing: WalletSpacing.sm) {
                    Text(Money.display(amount)).walletText(WalletType.displayBalance).foregroundStyle(WalletColors.textPrimary)
                        .accessibilityIdentifier("result-amount")
                    Text("TWD").walletText(WalletType.bodyStrong).foregroundStyle(WalletColors.textSecondary)
                }
                if replayed {
                    Message(kind: .success, text: Messages.replayed, testTag: "replayed")
                }
                WalletCard(spacing: 0, padding: EdgeInsets(top: WalletSpacing.xs, leading: WalletSpacing.xl,
                                                           bottom: WalletSpacing.xs, trailing: WalletSpacing.xl)) {
                    rows
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("result")
        }
    }
}
