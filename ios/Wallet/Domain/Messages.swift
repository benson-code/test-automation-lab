/// What the user reads for each API error code (SPEC.md §6.6). The server decides; the client only
/// explains the decision. Same texts as web/src/messages.js and the Android Messages.kt.
nonisolated enum Messages {
    private static let byCode = [
        "INVALID_AMOUNT": "Enter an amount like 100 or 100.50: more than 0, at most two decimals.",
        "INSUFFICIENT_BALANCE": "Not enough balance for this payment.",
        "LIMIT_EXCEEDED": "This is above the single-payment limit of 50,000.00.",
        "REFUND_EXCEEDS_PAYMENT": "This refund would exceed what is left to refund on this payment.",
        "WALLET_NOT_FOUND": "No wallet with this ID.",
        "PAYMENT_NOT_FOUND": "No payment with this ID.",
        "INVALID_OWNER": "Enter a name of 1 to 50 characters.",
        "IDEMPOTENCY_KEY_REUSED": "This request conflicts with an earlier one. Start again.",
    ]

    /// The codes with a text of their own (SPEC §6.6); MessagesSpecParityTests compares them with SPEC.md.
    static var codes: [String] { Array(byCode.keys) }

    static func forCode(_ code: String) -> String { byCode[code] ?? "Something went wrong (\(code))." }

    static let noAnswerTryAgain = "No answer from the server. Try again."
    static let noAnswer = "No answer from the server."
    static let payNoAnswer =
        "No answer from the server. The payment may or may not have gone through. Retrying is safe: it cannot charge twice."
    static let refundNoAnswer =
        "No answer from the server. The refund may or may not have gone through. Retrying is safe: it cannot refund twice."
    static let replayed = "This payment had already gone through. You were not charged again."
    static let topUpNoAnswer =
        "No answer from the server: the top-up may or may not have gone through. Check the balance before trying again."
}
