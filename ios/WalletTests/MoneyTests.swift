import XCTest
@testable import Wallet

/// Money: amounts as text and integer cents, never floating point (SPEC.md D-01, R-04). Same cases as the
/// Android MoneyTest.
final class MoneyTests: XCTestCase {
    func testDisplayGroupsThousandsAndKeepsTheCents() {
        XCTAssertEqual(Money.display("0.00"), "0.00")
        XCTAssertEqual(Money.display("999.99"), "999.99")
        XCTAssertEqual(Money.display("1000.00"), "1,000.00")
        XCTAssertEqual(Money.display("12345.60"), "12,345.60")
        XCTAssertEqual(Money.display("1234567.89"), "1,234,567.89")
        XCTAssertEqual(Money.display("-7.00"), "-7.00")
    }

    func testSignedUsesPlusAndTheTypographicMinus() {
        XCTAssertEqual(Money.signed("100.00"), "+100.00")
        XCTAssertEqual(Money.signed("-30.00"), "\u{2212}30.00")
        XCTAssertEqual(Money.signed("-1234.50"), "\u{2212}1,234.50")
    }

    func testCentsRoundTripWithoutFloatingPoint() {
        // 19.99 * 100 is 1998.9999... in floating point; the API's float_math defect loses that cent
        XCTAssertEqual(Money.toCents("19.99"), 1999)
        XCTAssertEqual(Money.toCents("100.5"), 10050)
        XCTAssertEqual(Money.toCents("30"), 3000)
        XCTAssertEqual(Money.toCents("-0.05"), -5)
        XCTAssertEqual(Money.fromCents(1999), "19.99")
        XCTAssertEqual(Money.fromCents(-5), "-0.05")
        XCTAssertEqual(Money.fromCents(0), "0.00")
        XCTAssertEqual(Money.fromCents(5_000_000), "50000.00")
    }

    func testLongBalancesStepDownTheTextStyle() {
        XCTAssertEqual(Money.balanceStyle("999,999.99"), "Display/Balance")
        XCTAssertEqual(Money.balanceStyle("••••••"), "Display/Balance")
        XCTAssertEqual(Money.balanceStyle("1,000,000.00"), "Amount/Large")
        XCTAssertEqual(Money.balanceStyle("999,999,999.99"), "Amount/Large")
        XCTAssertEqual(Money.balanceStyle("1,000,000,000.00"), "Title/Large")
        XCTAssertEqual(Money.balanceStyle("999,999,999,999.99"), "Title/Large")
    }

    func testPlainAmountsAreAsciiDigitsOnly() {
        // The pattern runs in ICU, as on the device: there `\d` matches any script's digits, and "１００"
        // was shown as 100.00 on Android's Confirm (SPEC §11, 2.3). The pattern writes [0-9] for that reason.
        for other in ["１００", "٣٠", "10０", "１.５０", "३०"] {
            XCTAssertFalse(Money.isPlain(other), other)
            XCTAssertNil(Money.normalize(other), other)
        }
        XCTAssertTrue(Money.isPlain("100.50"))
    }

    func testNormalizeAcceptsOnlyPlainAmounts() {
        XCTAssertEqual(Money.normalize("30"), "30.00")
        XCTAssertEqual(Money.normalize("30.5"), "30.50")
        XCTAssertEqual(Money.normalize("0.01"), "0.01")
        // The client does not validate (R-02): these go to the API as typed, and Confirm shows them as typed.
        // A final line break too: in ICU `$` matches before it, so the pattern ends with `\z`.
        for notPlain in ["", "-1", "1e3", "10.555", "1,000", "abc", ".5", "5.", " 30.5 ", "5 ", " 5", "30\n"] {
            XCTAssertNil(Money.normalize(notPlain), notPlain)
        }
    }

    func testPlainStopsAtTheApisTwelveDigits() {
        // The API takes at most 12 digits before the point (R-04). A longer amount is shown as typed and
        // never converted, so it cannot overflow 64 bits (a 20-digit amount crashed Android's Confirm, 2.11).
        XCTAssertEqual(Money.normalize("999999999999.99"), "999999999999.99")
        XCTAssertEqual(Money.toCents("999999999999.99"), 99_999_999_999_999)
        for tooLong in ["1000000000000", "9223372036854775807", "99999999999999999999"] {
            XCTAssertNil(Money.normalize(tooLong), tooLong)
        }
        XCTAssertNil(Money.toCents("99999999999999999999"), "does not fit in 64 bits")
        XCTAssertTrue(Money.sameAmount("99999999999999999999", "99999999999999999999"))
        XCTAssertFalse(Money.sameAmount("1000000000000", "1000000000000.00"))   // as typed: not the same text
    }

    func testSameAmountComparesMoneyNotText() {
        XCTAssertTrue(Money.sameAmount("30", "30.00"))
        XCTAssertFalse(Money.sameAmount(" 30.5", "30.50"))   // the API refuses " 30.5": not the same payment
        XCTAssertFalse(Money.sameAmount("30", "20"))
        XCTAssertTrue(Money.sameAmount("1e3", "1e3"))        // not plain: compared as typed
        XCTAssertFalse(Money.sameAmount("1e3", "1000"))
    }
}
