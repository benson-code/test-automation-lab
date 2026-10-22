import XCTest
@testable import Wallet

/// The error texts are part of the specification (SPEC.md §6.6) and must read the same on every client.
/// This test reads the table in SPEC.md and requires Messages to match it, row by row, as the Android
/// MessagesSpecParityTest does.
final class MessagesSpecParityTests: XCTestCase {
    func testEveryErrorTextMatchesTheSpecification() throws {
        let spec = try RepoFiles.text("SPEC.md")
        let row = try Regex(#"^\| E-0[0-9] \| `([A-Z_]+)` \| ([^|]+) \|"#).anchorsMatchLineEndings()
        var rows: [String: String] = [:]
        for match in spec.matches(of: row) {
            rows[String(match[1].substring!)] = match[2].substring!.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertGreaterThanOrEqual(rows.count, 8, "no error rows found in SPEC.md")
        let app = Dictionary(uniqueKeysWithValues: Messages.codes.map { ($0, Messages.forCode($0)) })
        XCTAssertEqual(app, rows)
    }

    func testUnknownCodesFollowTheSpecification() throws {
        let spec = try RepoFiles.text("SPEC.md")
        let row = try Regex(#"^\| E-09 \| any other code \| ([^|]+) \|"#).anchorsMatchLineEndings()
        let found = try XCTUnwrap(spec.firstMatch(of: row), "E-09 not found in SPEC.md")
        // SPEC writes the placeholder as `<code>`
        let expected = found[1].substring!.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "`<code>`", with: "SOMETHING_NEW")
        XCTAssertEqual(Messages.forCode("SOMETHING_NEW"), expected)
    }
}
