import Observation
import SwiftUI

/// Pay: enter the amount, review it on Confirm, then the receipt (SPEC.md §7.5). Same behaviour as
/// web/src/screens/Pay.jsx and the Android PayScreen.kt.
///
/// The Idempotency-Key is created when Confirm payment is tapped (Attempt). Confirm has four states:
/// ready, processing (a second tap sends nothing, Cancel and Back are disabled), refused (nothing was
/// charged; the next confirm is a new attempt) and no answer (Retry sends the same key again). After
/// no answer the attempt survives Back: continuing with the same amount shows "no answer" again, and
/// only a different amount starts a new attempt (K-05).
///
/// K-08: the step, the amount and a pending attempt (amount and key) are kept in the scene's saved state
/// (`Saved`, kept by WalletApp's @SceneStorage), so they survive the system ending the app in the
/// background. Reopened, the app shows Confirm with "no answer" and Retry resends the saved key: the web
/// cannot do this (SPEC.md §10). Android keeps the same in its SavedStateHandle.
///
/// N-01: the receipt is kept there too. Without it, an app ended on the receipt reopened on Confirm, ready
/// to send the same amount again with a new key: a second payment (found on Android in 2.3, APP-017).
@Observable
final class PayModel {
    nonisolated enum Step: String, Codable { case amount, confirm }

    struct Receipt {
        let payment: Payment
        let replayed: Bool
    }

    /// What is kept for K-08 and N-01. An attempt is kept only while its outcome may still be a charge
    /// (in flight or no answer), as on Android.
    nonisolated struct Saved: Codable, Equatable {
        var amount = ""
        var step = Step.amount
        var pendingAmount: String?
        var pendingKey: String?
        var receipt: SavedReceipt?
    }

    /// The receipt's fields, as on Android: what the receipt shows, so a payment that went through is never offered again.
    nonisolated struct SavedReceipt: Codable, Equatable {
        let paymentId: String
        let amount: String
        let createdAt: String
        let balanceAfter: String?
        let replayed: Bool
    }

    let attempt = Attempt(idempotent: true)
    var amount = ""
    private(set) var step = Step.amount
    private(set) var wallet: Wallet?
    private(set) var receipt: Receipt?
    private let api: ApiClient
    private let walletId: String

    init(api: ApiClient, walletId: String, saved: Saved? = nil) {
        self.api = api
        self.walletId = walletId
        guard let saved else { return }
        amount = saved.amount
        step = saved.step
        if let pendingAmount = saved.pendingAmount { attempt.restore(amount: pendingAmount, key: saved.pendingKey) }
        if let r = saved.receipt {
            receipt = Receipt(payment: Payment(paymentId: r.paymentId, walletId: walletId, amount: r.amount, refunded: "0.00",
                                               createdAt: r.createdAt, balanceAfter: r.balanceAfter, refunds: []),
                              replayed: r.replayed)
        }
    }

    /// This screen's state as K-08 and N-01 keep it.
    var saved: Saved {
        let keepAttempt = attempt.state == .pending || attempt.state == .unknown
        return Saved(amount: amount, step: step,
                     pendingAmount: keepAttempt ? attempt.pendingAmount : nil,
                     pendingKey: keepAttempt ? attempt.pendingKey : nil,
                     receipt: receipt.map {
                         SavedReceipt(paymentId: $0.payment.paymentId, amount: $0.payment.amount, createdAt: $0.payment.createdAt,
                                      balanceAfter: $0.payment.balanceAfter, replayed: $0.replayed)
                     })
    }

    func load() async {
        if case .ok(let w, _) = await api.getWallet(walletId) { wallet = w }
    }

    /// Continue: a different amount from a pending attempt's is a new payment.
    func toConfirm() {
        if let pending = attempt.pendingAmount, !Money.sameAmount(pending, amount) { attempt.reset() }
        step = .confirm
    }

    /// Back, Cancel or Change amount. A pending attempt is kept (K-05); a refusal's message is cleared.
    func changeAmount() {
        if attempt.state != .unknown { attempt.reset() }
        step = .amount
    }

    func confirm() async {
        let result = await attempt.submit(amount) { amount, key in await api.pay(walletId, amount, key: key!) }
        if case .ok(let payment, let replayed) = result {
            receipt = Receipt(payment: payment, replayed: replayed)
        }
    }
}

struct PayView: View {
    let onBack: () -> Void
    let onDone: () -> Void
    let onViewPayment: (_ paymentId: String) -> Void
    @Binding private var saved: PayModel.Saved?
    @State private var model: PayModel

    /// `saved`: the scene's saved state for this screen (K-08), read once here and written on every change.
    init(api: ApiClient, walletId: String, saved: Binding<PayModel.Saved?>, onBack: @escaping () -> Void,
         onDone: @escaping () -> Void, onViewPayment: @escaping (String) -> Void) {
        self.onBack = onBack
        self.onDone = onDone
        self.onViewPayment = onViewPayment
        _saved = saved
        _model = State(initialValue: PayModel(api: api, walletId: walletId, saved: saved.wrappedValue))
    }

    var body: some View {
        Group {
            if let receipt = model.receipt {
                receiptScreen(receipt)
            } else if model.step == .amount {
                amountScreen
            } else {
                confirmScreen
            }
        }
        .task { await model.load() }
        .onChange(of: model.saved) { _, now in saved = now }
    }

    private var amountScreen: some View {
        Screen(title: "Pay", onBack: onBack) {
            WalletButton(text: "Continue", testTag: "submit",
                         enabled: !model.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { model.toConfirm() }
        } content: {
            if let wallet = model.wallet { Available(wallet: wallet) }
            AmountField(value: $model.amount)
        }
    }

    /// The amount is shown as the API will read it when it is a plain amount, else as typed (R-04).
    private var confirmScreen: some View {
        let state = model.attempt.state
        let pending = state == .pending
        let normalized = Money.normalize(model.amount)
        let after: Int64? = if let normalized, let wallet = model.wallet,
                               let balance = Money.toCents(wallet.balance), let cents = Money.toCents(normalized) {
            balance - cents
        } else {
            nil
        }
        return Screen(title: "Confirm payment", onBack: { model.changeAmount() }, backEnabled: !pending) {
            switch state {
            case .unknown:
                WalletButton(text: "Retry", testTag: "retry") { Task { await model.confirm() } }
                WalletButton(text: "Back to wallet", testTag: "back-to-wallet", kind: .ghost, action: onDone)
            case .refused:
                WalletButton(text: "Confirm payment", testTag: "confirm-pay") { Task { await model.confirm() } }
                WalletButton(text: "Change amount", testTag: "change-amount", kind: .ghost) { model.changeAmount() }
            default:
                WalletButton(text: "Confirm payment", testTag: "confirm-pay", loading: pending) { Task { await model.confirm() } }
                WalletButton(text: "Cancel", testTag: "cancel", kind: .ghost, enabled: !pending) { model.changeAmount() }
            }
        } content: {
            WalletCard(spacing: WalletSpacing.xs) {
                Text("You pay").walletText(WalletType.label).foregroundStyle(WalletColors.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(normalized.map(Money.display) ?? model.amount).accessibilityIdentifier("confirm-amount")
                    Text(" TWD")
                }
                .walletText(WalletType.amountLarge)
                .foregroundStyle(WalletColors.textPrimary)
                // The rows touch, with a hairline between them, and the last one ends the card (SPEC §7.7)
                let showAfter = after.map { $0 >= 0 } ?? false
                VStack(spacing: 0) {
                    if let wallet = model.wallet {
                        ReceiptRow(label: "From", value: "\(wallet.owner) · \(Formats.maskId(wallet.walletId))", last: !showAfter)
                    }
                    if let after, showAfter {
                        RowDivider()
                        ReceiptRow(label: "Balance after", value: Money.display(Money.fromCents(after)),
                                   valueTestTag: "confirm-balance-after", suffix: "TWD", last: true)
                    }
                }
            }
            switch state {
            case .refused(_, let message): Message(kind: .error, text: message, testTag: "error-message")
            case .unknown: Message(kind: .warning, text: Messages.payNoAnswer, testTag: "no-answer")
            default: EmptyView()
            }
        }
    }

    /// The receipt: Done goes Home, View payment opens the payment's detail (SPEC §4).
    private func receiptScreen(_ receipt: PayModel.Receipt) -> some View {
        let p = receipt.payment
        return Receipt(title: "Payment", heading: "Payment completed", amount: p.amount, replayed: receipt.replayed) {
            WalletButton(text: "Done", testTag: "done", action: onDone)
            WalletButton(text: "View payment", testTag: "view-payment", kind: .ghost) { onViewPayment(p.paymentId) }
        } rows: {
            ReceiptRow(label: "Status", value: "Completed")
            RowDivider()
            ReceiptRow(label: "Time", value: Formats.dateTime(p.createdAt))
            RowDivider()
            ReceiptRow(label: "Payment ID", value: p.paymentId, valueTestTag: "result-payment-id")
            if let balance = p.balanceAfter {
                RowDivider()
                ReceiptRow(label: "Balance after", value: Money.display(balance), valueTestTag: "result-balance", suffix: "TWD")
            }
        }
    }
}

/// "Available 68.00 TWD"; the hook "balance" holds the number only.
struct Available: View {
    let wallet: Wallet

    var body: some View {
        HStack(spacing: 0) {
            Text("Available ")
            Text(Money.display(wallet.balance)).accessibilityIdentifier("balance")
            Text(" \(wallet.currency)")
        }
        .walletText(WalletType.body)
        .foregroundStyle(WalletColors.textSecondary)
    }
}
