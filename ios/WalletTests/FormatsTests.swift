import XCTest
@testable import Wallet

/// Dates in the device's time zone, masked IDs and entry labels (SPEC.md D-03, D-04). The scheme runs the
/// tests with TZ=Asia/Taipei, as the UI tests launch the app. Same cases as the Android FormatsTest.
final class FormatsTests: XCTestCase {
    /// 10 Oct 2026, 12:00 in Taipei (UTC+8).
    private let now = ISO8601DateFormatter().date(from: "2026-10-10T04:00:00Z")!

    private func inTaipei() throws {
        XCTAssertEqual(TimeZone.current.identifier, "Asia/Taipei", "run with the Wallet scheme, which sets TZ")
    }

    func testTimesAreShownInTheDeviceTimeZone() throws {
        try inTaipei()
        XCTAssertEqual(Formats.time("2026-10-10T06:31:12.345+00:00"), "14:31")
        XCTAssertEqual(Formats.dateTime("2026-10-10T06:31:12.345+00:00"), "10 Oct 2026, 14:31")
    }

    func testDayLabelsUseTheLocalDate() throws {
        try inTaipei()
        // 16:30 UTC on 9 Oct is 00:30 on 10 Oct in Taipei: "Today", not "Yesterday"
        XCTAssertEqual(Formats.dayLabel("2026-10-09T16:30:00.000+00:00", now: now), "Today")
        XCTAssertEqual(Formats.dayLabel("2026-10-09T15:59:00.000+00:00", now: now), "Yesterday")
        XCTAssertEqual(Formats.dayLabel("2026-10-08T15:00:00.000+00:00", now: now), "8 Oct")
        XCTAssertEqual(Formats.dayLabel("2025-12-31T01:00:00.000+00:00", now: now), "31 Dec 2025")
    }

    func testGroupingKeepsTheOrder() throws {
        try inTaipei()
        let items = ["2026-10-09T16:30:00.000+00:00", "2026-10-09T16:31:00.000+00:00", "2026-10-09T15:59:00.000+00:00"]
        let groups = Formats.groupByDay(items, now: now) { $0 }
        XCTAssertEqual(groups.map(\.label), ["Today", "Yesterday"])
        XCTAssertEqual(groups.map(\.items.count), [2, 1])
    }

    func testWalletIdsAreMasked() {
        XCTAssertEqual(Formats.maskId("w_beeb1c2d3e4f4385"), "w_beeb •••• 4385")
        XCTAssertEqual(Formats.maskId("w_short"), "w_short")
    }

    func testEntryTypesHaveLabels() {
        XCTAssertEqual(Formats.typeLabel("TOPUP"), "Top-up")
        XCTAssertEqual(Formats.typeLabel("PAYMENT"), "Payment")
        XCTAssertEqual(Formats.typeLabel("SOMETHING_NEW"), "SOMETHING_NEW")
    }
}
