# Wallet — iOS app

The native iOS client of the wallet: Swift and SwiftUI, the same rules as the web page (`../web/`) and
the Android app (`../android/`), all defined by [`../SPEC.md`](../SPEC.md). Its Appium tests live with
the rest of the suite, in [`../tests/ios/`](../tests/ios/) (IOS-001 to 006, 008 to 010, 014, 015, 017 to 020;
how to run them: the main README, section 4).

**Screens.** Every screen of the web page and the Android app, in two stages. The first (SPEC 2.10):
Start (create or open a wallet), Home (balance, the latest entries) and Pay (amount → Confirm →
receipt, with the four Confirm states and the `replayed` receipt). The second (SPEC 2.14): the tab bar,
History (grouped by day), Top up (no Retry after no answer, K-07), Payment detail with refunds (Retry
with the same key), payment rows that open their detail, and *View payment* on the payment receipt.
Since SPEC 2.15 a pending payment and its receipt survive iOS ending the app in the background (K-08,
IOS-015 and IOS-017), kept in the scene's saved state (`@SceneStorage`). Not yet: unit tests and CI.

## Build

Built and tested with Xcode 27 and the iOS 26 simulator. It needs Xcode 26 or later: the code runs on
the main actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION`), a Swift 6.2 setting. The app supports
iOS 17 and later. No signing is needed for the simulator.

```bash
xcodebuild -project ios/Wallet.xcodeproj -scheme Wallet -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath ios/build build
# ios/build/Build/Products/Debug-iphonesimulator/Wallet.app
```

Run it by hand against a local API:

```bash
DB_PATH=wallet.db .venv/bin/uvicorn app.main:app --port 8400     # the app's default address
xcrun simctl boot "iPhone 17"
xcrun simctl install booted ios/build/Build/Products/Debug-iphonesimulator/Wallet.app
xcrun simctl launch booted lab.wallet                            # or: -apiBaseUrl http://127.0.0.1:<port>
```

## How it reaches the API

The simulator shares the Mac's network, so `127.0.0.1` in the app is the Mac: no forwarding, unlike
Android's `adb reverse`. Debug builds take another address from the launch argument
`-apiBaseUrl <url>` (the same name as the Android launch extra); the tests use it to put the test proxy
in between. Release builds ignore it. `Info.plist` allows plain HTTP to local addresses only
(`NSAllowsLocalNetworking`), as the Android app's network security config does.

Requests use an ephemeral `URLSession` with no cache: a balance must come from the server, never from a
stored answer.

## Project

`Wallet.xcodeproj` is written by hand and small: the `Wallet/` folder is a synchronised group, so a new
Swift file needs no change to the project file.

```
ios/
├── Wallet.xcodeproj/
├── Info.plist                 Merged with Xcode's generated keys: local HTTP, the Inter fonts
└── Wallet/
    ├── WalletApp.swift        Entry point and the routes (SPEC §4); Payment detail goes back to History;
    │                          the screen and Pay's state kept in the scene's saved state (K-08)
    ├── Data/                  ApiConfig (launch argument), ApiClient (URLSession), Models (parsed by hand)
    ├── Domain/                Money (integer cents), Formats, Messages, Attempt (K-01 to K-05, K-08)
    └── UI/
        ├── Theme/             DesignTokens (Figma names), Theme (colours, spacing, text styles)
        ├── Components/        One per Figma component: WalletButton, AmountField, Message, TopBar, TabBar, rows, BalanceCard
        └── Screens/           StartView, HomeView, HistoryView, TopUpView, PayView, PaymentDetailView, Receipt
```

The code follows the Android app file by file (`Attempt.swift` ↔ `Attempt.kt`, `PayView.swift` ↔
`PayScreen.kt`), so a rule can be compared across the two.

## Design system

- `UI/Theme/DesignTokens.swift` holds the colours, spacing, radii and text styles under their Figma
  names, copied from the Android app's `DesignTokens.kt`. When this stage was written all 25 colours,
  12 spacing and radius values and 8 text styles were equal to `web/src/tokens.css` and the Kotlin
  file; unlike Android's `DesignTokenParityTest`, nothing checks this on every change yet.
- The Inter font files are not copied: the project file points at the Android app's
  `res/font/*.ttf`, so both apps ship the same files.
- Icons are SF Symbols, not the Figma file's line icons.
- Text styles scale with the user's text size (Dynamic Type); touch targets are at least 44 × 44 pt.

## Test hooks

Every hook is a SwiftUI `accessibilityIdentifier` with the same name as the web's `data-testid` and the
Android app's `testTag` (SPEC.md §7). Appium finds them with the accessibility id strategy. Three things
XCUITest does differently from UiAutomator, handled once in `framework/ios/base.py`:

- Elements outside the visible part of a scroll view are in the tree, and tapping one scrolls to it.
- A button's text is its label: SwiftUI merges a button's content into one element. A payment row is a
  button whose texts keep their own hooks (`item-title` …): its content stays separate elements, as
  long as the button itself is not made an accessibility container, which would replace its hook
  `open-payment` with one built from its children's (`TransactionRow` in `Rows.swift`).
- An empty text field's value is its placeholder (`0.00`), not an empty string.

Visible field labels are hidden from VoiceOver and given to the field as its name instead, so a field is
read once, by its label (SPEC L-03).
