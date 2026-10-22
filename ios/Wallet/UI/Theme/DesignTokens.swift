import CoreGraphics

/// The design tokens of the Figma file "Wallet – UI Spec" (Foundations page), keyed by their Figma
/// names, copied from the Android app's DesignTokens.kt. The web declares the same values in
/// web/src/tokens.css. A value is changed in Figma first, then in all three places. Android's
/// DesignTokenParityTest compares its copy with tokens.css, and DesignTokenParityTests compares this one
/// (ios/WalletTests).
///
/// Plain values, no SwiftUI types: Theme.swift turns them into colours, fonts and sizes.
enum DesignTokens {

    /// Semantic colours (Figma collection "Color"), RGB. Primitives are not exposed.
    static let colors: [String: UInt32] = [
        "color/bg/page": 0xF8F8F6,
        "color/bg/surface": 0xFFFFFF,
        "color/bg/subtle": 0xF1F1EE,
        "color/text/primary": 0x16181C,
        "color/text/secondary": 0x62666D,
        "color/text/on-primary": 0xFFFFFF,
        "color/text/link": 0x2E4366,
        "color/border/default": 0xE6E6E2,
        "color/border/strong": 0xC8C9C5,
        "color/border/focus": 0x1B2A41,
        "color/action/primary": 0x1B2A41,
        "color/action/primary-pressed": 0x2E4366,
        "color/action/secondary": 0xF0F3F8,
        "color/action/on-secondary": 0x1B2A41,
        "color/amount/credit": 0x12704C,
        "color/amount/debit": 0xB42318,
        "color/feedback/error-bg": 0xFDEEEC,
        "color/feedback/error-text": 0xB42318,
        "color/feedback/warning-bg": 0xFFF6E3,
        "color/feedback/warning-text": 0x7A4E00,
        "color/feedback/success-bg": 0xEAF5EF,
        "color/feedback/success-text": 0x12704C,
        "color/icon/default": 0x16181C,
        "color/icon/muted": 0x62666D,
        "color/icon/on-primary": 0xFFFFFF,
    ]

    /// Spacing (Figma collection "Spacing"), in points.
    static let spacing: [String: CGFloat] = [
        "spacing/xs": 4,
        "spacing/sm": 8,
        "spacing/md": 12,
        "spacing/lg": 16,
        "spacing/xl": 20,
        "spacing/2xl": 24,
        "spacing/3xl": 32,
    ]

    /// Corner radius (Figma collection "Radius"), in points.
    static let radius: [String: CGFloat] = [
        "radius/sm": 8,
        "radius/md": 10,
        "radius/lg": 12,
        "radius/xl": 16,
        "radius/full": 999,
    ]

    /// One Figma text style. Sizes in points, letter spacing in em (Figma's percent / 100).
    struct TextToken {
        let weight: Int
        let size: CGFloat
        let lineHeight: CGFloat
        let letterSpacingEm: CGFloat
    }

    /// Text styles (Inter), under their Figma names.
    static let text: [String: TextToken] = [
        "Display/Balance": TextToken(weight: 700, size: 40, lineHeight: 48, letterSpacingEm: -0.02),
        "Amount/Large": TextToken(weight: 600, size: 28, lineHeight: 34, letterSpacingEm: -0.01),
        "Title/Large": TextToken(weight: 600, size: 22, lineHeight: 28, letterSpacingEm: -0.005),
        "Title/Medium": TextToken(weight: 600, size: 17, lineHeight: 24, letterSpacingEm: 0.0),
        "Body/Regular": TextToken(weight: 400, size: 15, lineHeight: 22, letterSpacingEm: 0.0),
        "Body/Strong": TextToken(weight: 500, size: 15, lineHeight: 22, letterSpacingEm: 0.0),
        "Label": TextToken(weight: 500, size: 13, lineHeight: 18, letterSpacingEm: 0.0),
        "Caption": TextToken(weight: 400, size: 13, lineHeight: 18, letterSpacingEm: 0.0),
    ]
}
