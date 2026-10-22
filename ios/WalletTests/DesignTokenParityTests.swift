import XCTest
@testable import Wallet

/// The three clients take their design tokens from the same Figma file (SPEC.md §3). This test reads the
/// web's web/src/tokens.css and requires DesignTokens.swift to hold exactly the same values, as the
/// Android DesignTokenParityTest does, so a change made on one client only fails the build.
///
/// Figma names map to CSS names by rule: color/bg/page -> --color-bg-page. Text styles have short CSS
/// class names, listed in textClasses.
final class DesignTokenParityTests: XCTestCase {
    private static let textClasses = [
        "Display/Balance": "t-display",
        "Amount/Large": "t-amount",
        "Title/Large": "t-title-lg",
        "Title/Medium": "t-title-md",
        "Body/Regular": "t-body",
        "Body/Strong": "t-body-strong",
        "Label": "t-label",
        "Caption": "t-caption",
    ]

    private func css() throws -> String { try RepoFiles.text("tokens.css") }
    private func cssName(_ figmaName: String) -> String { figmaName.replacingOccurrences(of: "/", with: "-") }

    func testColoursMatchTheWeb() throws {
        var web: [String: String] = [:]
        for m in try css().matches(of: try Regex(#"--(color-[a-z0-9-]+):\s*#([0-9a-fA-F]{6});"#)) {
            web[String(m[1].substring!)] = "#" + m[2].substring!.uppercased()
        }
        let app = Dictionary(uniqueKeysWithValues: DesignTokens.colors.map { (cssName($0.key), String(format: "#%06X", $0.value)) })
        XCTAssertFalse(web.isEmpty, "no colours found in tokens.css")
        XCTAssertEqual(app, web)
    }

    func testColoursAreSixDigitRgb() {
        // tokens.css has no alpha; a value above 0xFFFFFF would be read as something else
        for (name, rgb) in DesignTokens.colors { XCTAssertLessThanOrEqual(rgb, 0xFFFFFF, name) }
    }

    func testSpacingAndRadiusMatchTheWeb() throws {
        for (prefix, tokens) in [("spacing", DesignTokens.spacing), ("radius", DesignTokens.radius)] {
            var web: [String: CGFloat] = [:]
            for m in try css().matches(of: try Regex("--(\(prefix)-[a-z0-9]+):\\s*([0-9]+)px;")) {
                web[String(m[1].substring!)] = CGFloat(Int(m[2].substring!)!)
            }
            let app = Dictionary(uniqueKeysWithValues: tokens.map { (cssName($0.key), $0.value) })
            XCTAssertFalse(web.isEmpty, "no \(prefix) tokens found in tokens.css")
            XCTAssertEqual(app, web, prefix)
        }
    }

    func testTextStylesMatchTheWeb() throws {
        // tokens.css writes text styles as longhands (font-weight, font-size, ...), never the font shorthand
        var web: [String: String] = [:]
        for m in try css().matches(of: try Regex(#"\.(t-[a-z-]+) \{([^}]*)\}"#)) {
            let body = String(m[2].substring!)
            func prop(_ name: String) throws -> String? {
                try body.firstMatch(of: try Regex("(?:^|;)\\s*\(name):\\s*([^;]+);"))
                    .map { $0[1].substring!.trimmingCharacters(in: .whitespaces) }
            }
            let weight = try prop("font-weight") ?? "?", size = try prop("font-size") ?? "?"
            let lineHeight = try prop("line-height") ?? "?", tracking = try prop("letter-spacing") ?? "0em"
            web[String(m[1].substring!)] = "\(weight) \(size) \(lineHeight) \(tracking)"
        }
        var app: [String: String] = [:]
        for (figmaName, t) in DesignTokens.text {
            let cls = try XCTUnwrap(Self.textClasses[figmaName], "no CSS class listed for text style \(figmaName)")
            let tracking = t.letterSpacingEm == 0 ? "0em" : "\(Double(t.letterSpacingEm))em"
            app[cls] = "\(t.weight) \(Int(t.size))px \(Int(t.lineHeight))px \(tracking)"
        }
        XCTAssertFalse(web.isEmpty, "no text styles found in tokens.css")
        XCTAssertEqual(app, web)
    }
}
