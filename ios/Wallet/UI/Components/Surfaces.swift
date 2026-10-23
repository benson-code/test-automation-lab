import SwiftUI

/// A surface with a hairline border, the web's `.card`: no shadow, radius 16, padding 20.
struct WalletCard<Content: View>: View {
    var spacing = WalletSpacing.md
    var padding = EdgeInsets(top: WalletSpacing.xl, leading: WalletSpacing.xl, bottom: WalletSpacing.xl, trailing: WalletSpacing.xl)
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WalletRadius.xl)
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(WalletColors.bgSurface, in: shape)
            .overlay(shape.strokeBorder(WalletColors.borderDefault, lineWidth: 1))
    }
}

enum MessageKind { case error, warning, success }

/// Figma: Message (Kind = Error | Warning | Success). Error: refused, nothing charged. Warning: no
/// answer, outcome unknown. Success: a confirmation. VoiceOver announces it when it appears.
///
/// The hook (`testTag`) is on the text itself, so a test reads the message from the hook's element,
/// as on Android.
struct Message: View {
    let kind: MessageKind
    let text: String
    let testTag: String

    var body: some View {
        let (bg, fg, icon): (Color, Color, String) = switch kind {
        case .error: (WalletColors.errorBg, WalletColors.errorText, "exclamationmark.circle")
        case .warning: (WalletColors.warningBg, WalletColors.warningText, "exclamationmark.circle")
        case .success: (WalletColors.successBg, WalletColors.successText, "checkmark.circle")
        }
        HStack(alignment: .top, spacing: WalletSpacing.md) {
            // The icon takes the 24 pt box of the web's and Android's icons, so the text starts where theirs does
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(fg).frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(text)
                .walletText(WalletType.body)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(testTag)
        }
        .padding(.horizontal, WalletSpacing.lg)
        .padding(.vertical, WalletSpacing.md)
        .background(bg, in: RoundedRectangle(cornerRadius: WalletRadius.lg))
        .onAppear { AccessibilityNotification.Announcement(text).post() }
    }
}

/// Figma: Top bar (Back = True | False). 56 pt, title centred. With `onBack` it shows a back button
/// (hook "back"), a 44 pt touch target; `backEnabled` = false while a request is in flight (K-02).
/// 8 pt at the sides, as on the web: the back icon's centre is 30 pt from the edge (SPEC §7.7).
struct TopBar: View {
    let title: String
    var onBack: (() -> Void)?
    var backEnabled = true

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if let onBack {
                    IconButton(systemName: "chevron.left", label: "Back", testTag: "back", enabled: backEnabled, action: onBack)
                }
            }
            .frame(width: minTouchTarget, height: minTouchTarget)
            Text(title)
                .walletText(WalletType.titleMedium)
                .foregroundStyle(WalletColors.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Color.clear.frame(width: minTouchTarget, height: minTouchTarget)
        }
        .padding(.horizontal, WalletSpacing.sm)
        .frame(height: 56)
    }
}

/// A screen: top bar, scrollable content, then either a tab bar (Home, History) or the screen's own
/// bottom actions, which stay above the keyboard. The same padding as the web's `.content`: 16 top,
/// 20 sides, 16 between blocks, 24 at the end, also under the bottom actions (SPEC §7.7).
///
/// The content can scroll a part of itself into view through `scrollProxy` in the environment (L-04).
struct Screen<Content: View, Bottom: View>: View {
    let title: String
    var onBack: (() -> Void)?
    var backEnabled = true
    var tabBar: TabBar?
    @ViewBuilder let bottom: Bottom
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: title, onBack: onBack, backEnabled: backEnabled)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: WalletSpacing.lg) { content }
                        .padding(.horizontal, WalletSpacing.xl)
                        .padding(.top, WalletSpacing.lg)
                        .padding(.bottom, WalletSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .environment(\.scrollProxy, proxy)
            }
            if !(bottom is EmptyView) {
                VStack(spacing: WalletSpacing.sm) { bottom }
                    .padding(.horizontal, WalletSpacing.xl)
                    .padding(.bottom, WalletSpacing.xxl)
            }
            if let tabBar { tabBar }
        }
        .background(WalletColors.bgPage)
    }
}

extension Screen where Bottom == EmptyView {
    init(title: String, onBack: (() -> Void)? = nil, backEnabled: Bool = true, tabBar: TabBar? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, onBack: onBack, backEnabled: backEnabled, tabBar: tabBar, bottom: { EmptyView() }, content: content)
    }
}

extension EnvironmentValues {
    /// The screen's scroll view, for content that must bring a part of itself into view (L-04).
    @Entry var scrollProxy: ScrollViewProxy?
}
