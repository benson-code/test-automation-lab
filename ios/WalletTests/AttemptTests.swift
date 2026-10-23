import XCTest
@testable import Wallet

/// The attempt's rules (SPEC.md §6.2, K-01 to K-08). Same cases as the Android AttemptTest.
///
/// The in-flight guard (K-02) is proven here only: the UI tests cannot reach it, since a second tap
/// arrives after the button has been redrawn disabled (SPEC §9).
final class AttemptTests: XCTestCase {
    /// A fake API: records what was sent, answers in order.
    private final class FakeApi {
        var sent: [(amount: String, key: String?)] = []
        var answers: [ApiResult<String>] = []

        func send(_ amount: String, _ key: String?) async -> ApiResult<String> {
            sent.append((amount, key))
            return answers.removeFirst()
        }
    }

    /// A request that waits until the test answers it.
    private final class HeldRequest {
        var calls = 0
        var answer: CheckedContinuation<ApiResult<String>, Never>?
    }

    private var counter = 0
    private func attempt(idempotent: Bool = true) -> Attempt {
        Attempt(idempotent: idempotent) { [unowned self] in counter += 1; return "key-\(counter)" }
    }
    private let ok = ApiResult<String>.ok("done")
    private let refused = ApiResult<String>.refused(status: 409, code: "INSUFFICIENT_BALANCE", message: "")

    func testAKeyIsCreatedOnlyWhenTheAttemptIsSent() async {
        let a = attempt()
        XCTAssertNil(a.pendingKey)
        XCTAssertEqual(counter, 0, "no key before the first submit (K-01)")
        let api = FakeApi()
        api.answers = [.noAnswer]
        _ = await a.submit("30", send: api.send)
        XCTAssertEqual(api.sent.map(\.amount), ["30"])
        XCTAssertEqual(api.sent.map(\.key), ["key-1"])
    }

    func testNoAnswerKeepsTheKeyForTheRetry() async {
        let a = attempt()
        let api = FakeApi()
        api.answers = [.noAnswer, ok]
        _ = await a.submit("30", send: api.send)
        XCTAssertEqual(a.state, .unknown)
        _ = await a.submit("30", send: api.send)
        XCTAssertEqual(api.sent[0].key, api.sent[1].key)
        XCTAssertEqual(a.state, .idle)
        XCTAssertNil(a.pendingAmount, "a successful attempt ends")
    }

    func testTheSameAmountWrittenDifferentlyKeepsTheKey() async {
        let a = attempt()
        let api = FakeApi()
        api.answers = [.noAnswer, ok]
        _ = await a.submit("30", send: api.send)
        _ = await a.submit("30.00", send: api.send)
        XCTAssertEqual(api.sent[0].key, api.sent[1].key)
        XCTAssertEqual(api.sent[1].amount, "30", "the pending attempt's own amount is resent")
    }

    func testADifferentAmountStartsANewAttempt() async {
        let a = attempt()
        let api = FakeApi()
        api.answers = [.noAnswer, ok]
        _ = await a.submit("30", send: api.send)
        _ = await a.submit("20", send: api.send)
        XCTAssertNotEqual(api.sent[0].key, api.sent[1].key)
        XCTAssertEqual(api.sent[1].amount, "20")
    }

    func testAnErrorAnswerEndsTheAttempt() async {
        let a = attempt()
        let api = FakeApi()
        api.answers = [refused, ok]
        _ = await a.submit("30", send: api.send)
        XCTAssertEqual(a.state, .refused(code: "INSUFFICIENT_BALANCE", message: "Not enough balance for this payment."))
        XCTAssertNil(a.pendingAmount)
        _ = await a.submit("30", send: api.send)
        XCTAssertNotEqual(api.sent[0].key, api.sent[1].key)
    }

    func testASecondSubmitWhileInFlightSendsNothing() async {
        let a = attempt()
        let held = HeldRequest()
        let first = Task {
            await a.submit("30") { _, _ in
                held.calls += 1
                return await withCheckedContinuation { held.answer = $0 }
            }
        }
        while held.answer == nil { await Task.yield() }       // the first submit is now waiting for its answer
        XCTAssertEqual(a.state, .pending)
        let second = await a.submit("30") { _, _ in held.calls += 1; return self.ok }
        XCTAssertNil(second, "the second submit is ignored")
        held.answer?.resume(returning: ok)
        _ = await first.value
        XCTAssertEqual(held.calls, 1)
    }

    func testResetIsIgnoredWhileInFlight() async {
        let a = attempt()
        let held = HeldRequest()
        let first = Task {
            await a.submit("30") { _, _ in await withCheckedContinuation { held.answer = $0 } }
        }
        while held.answer == nil { await Task.yield() }
        a.reset()
        XCTAssertEqual(a.state, .pending)
        held.answer?.resume(returning: .noAnswer)
        _ = await first.value
        XCTAssertEqual(a.pendingAmount, "30")
    }

    func testTopUpsSendNoKey() async {
        let a = attempt(idempotent: false)
        let api = FakeApi()
        api.answers = [.noAnswer, ok]
        _ = await a.submit("10", send: api.send)
        XCTAssertEqual(a.state, .unknown)
        _ = await a.submit("10", send: api.send)
        XCTAssertTrue(api.sent.allSatisfy { $0.key == nil }, "K-07: the top-up API takes no key")
    }

    func testClearRefusalKeepsAPendingAttempt() async {
        let a = attempt()
        let api = FakeApi()
        api.answers = [.noAnswer]
        _ = await a.submit("30", send: api.send)
        a.clearRefusal()
        XCTAssertEqual(a.state, .unknown, "no answer is not a refusal: it stays")
        XCTAssertEqual(a.pendingAmount, "30")
    }

    func testARestoredAttemptResendsItsKey() async {
        // K-08: iOS ended the app while the outcome was unknown; the saved amount and key come back
        let a = attempt()
        a.restore(amount: "30", key: "saved-key")
        XCTAssertEqual(a.state, .unknown)
        let api = FakeApi()
        api.answers = [ok]
        _ = await a.submit("30.00", send: api.send)
        XCTAssertEqual(api.sent.map(\.amount), ["30"])
        XCTAssertEqual(api.sent.map(\.key), ["saved-key"])
    }

    func testARestoredAttemptEndsWhenTheAmountChanges() async {
        let a = attempt()
        a.restore(amount: "30", key: "saved-key")
        let api = FakeApi()
        api.answers = [ok]
        _ = await a.submit("20", send: api.send)
        XCTAssertEqual(api.sent.map(\.key), ["key-1"])
    }
}
