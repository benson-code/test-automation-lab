import SwiftUI
import UIKit

/// DesignTokens as SwiftUI values, under the same names as the Android theme (Theme.kt).

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }
}

enum WalletColors {
    private static func token(_ name: String) -> Color { Color(rgb: DesignTokens.colors[name]!) }

    static let bgPage = token("color/bg/page")
    static let bgSurface = token("color/bg/surface")
    static let textPrimary = token("color/text/primary")
    static let textSecondary = token("color/text/secondary")
    static let textOnPrimary = token("color/text/on-primary")
    static let textLink = token("color/text/link")
    static let borderDefault = token("color/border/default")
    static let borderFocus = token("color/border/focus")
    static let actionPrimary = token("color/action/primary")
    static let actionPrimaryPressed = token("color/action/primary-pressed")
    static let actionSecondary = token("color/action/secondary")
    static let actionOnSecondary = token("color/action/on-secondary")
    static let amountCredit = token("color/amount/credit")
    static let errorBg = token("color/feedback/error-bg")
    static let errorText = token("color/feedback/error-text")
    static let warningBg = token("color/feedback/warning-bg")
    static let warningText = token("color/feedback/warning-text")
    static let successBg = token("color/feedback/success-bg")
    static let successText = token("color/feedback/success-text")
    static let iconDefault = token("color/icon/default")
    static let iconMuted = token("color/icon/muted")
}

enum WalletSpacing {
    static let xs = DesignTokens.spacing["spacing/xs"]!
    static let sm = DesignTokens.spacing["spacing/sm"]!
    static let md = DesignTokens.spacing["spacing/md"]!
    static let lg = DesignTokens.spacing["spacing/lg"]!
    static let xl = DesignTokens.spacing["spacing/xl"]!
    static let xxl = DesignTokens.spacing["spacing/2xl"]!
}

enum WalletRadius {
    static let sm = DesignTokens.radius["radius/sm"]!
    static let md = DesignTokens.radius["radius/md"]!
    static let lg = DesignTokens.radius["radius/lg"]!
    static let xl = DesignTokens.radius["radius/xl"]!
}

/// Apple's minimum touch target (Human Interface Guidelines); Android uses 48 dp, the web 44 CSS px (SPEC §5).
let minTouchTarget: CGFloat = 44

/// A Figma text style: Inter at the token's size, scaled with the user's text size (Dynamic Type).
struct WalletTextStyle {
    let font: Font
    let tracking: CGFloat
    /// The token's line height minus Inter's own (22 - 18.15 for Body). SwiftUI has no line height (§5).
    let leading: CGFloat
}

enum WalletType {
    static let displayBalance = style("Display/Balance", tabular: true)
    static let amountLarge = style("Amount/Large", tabular: true)
    static let titleLarge = style("Title/Large")
    static let titleLargeTabular = style("Title/Large", tabular: true)
    static let titleMedium = style("Title/Medium")
    static let body = style("Body/Regular")
    static let bodyStrong = style("Body/Strong")
    static let bodyStrongTabular = style("Body/Strong", tabular: true)
    static let label = style("Label")
    static let caption = style("Caption")

    /// The PostScript names of the bundled Inter files (Info.plist, UIAppFonts).
    private static let faces = [400: "Inter-Regular", 500: "Inter-Medium", 600: "Inter-SemiBold", 700: "Inter-Bold"]

    private static func style(_ name: String, tabular: Bool = false) -> WalletTextStyle {
        let t = DesignTokens.text[name]!
        let face = faces[t.weight]!
        var font = Font.custom(face, size: t.size, relativeTo: .body)
        if tabular { font = font.monospacedDigit() }
        let natural = UIFont(name: face, size: t.size)?.lineHeight ?? t.size * 1.2
        return WalletTextStyle(font: font, tracking: t.size * t.letterSpacingEm, leading: max(0, t.lineHeight - natural))
    }
}

/// The token's line height, built from what SwiftUI has: the leading goes between lines (line spacing)
/// and half of it above and below the text, as CSS and Compose place it. With line spacing alone, a
/// line of Body was 18 pt high instead of 22, and every row was shorter than on the web and Android
/// (SPEC.md §11, 2.12; IOS-018). Scaled like the font, so the line height grows with Dynamic Type.
///
/// SwiftUI draws a Text one pixel taller than the font's own line height (measured for 2.16: Caption
/// 16.06 pt for 15.73 on a 3x screen, 16.23 on a 2x one), so that pixel comes off the padding: without
/// it a line was 1/3 pt taller than its token, and a History row 67.67 pt instead of 67.
private struct WalletText: ViewModifier {
    let style: WalletTextStyle
    @ScaledMetric private var leading: CGFloat
    @Environment(\.displayScale) private var displayScale

    init(_ style: WalletTextStyle) {
        self.style = style
        _leading = ScaledMetric(wrappedValue: style.leading, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(leading)
            .padding(.vertical, max(0, leading - 1 / displayScale) / 2)
    }
}

extension View {
    func walletText(_ style: WalletTextStyle) -> some View {
        modifier(WalletText(style))
    }
}
