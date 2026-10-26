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
IOS-015 and IOS-017), kept in the scene's saved state (`@SceneStorage`). Unit tests since SPEC 2.17
(below). In CI since SPEC 2.18 (main README, section 8).

## Build

Built and tested with Xcode 27 and the iOS 26 simulator on the Mac, and with Xcode 26.6 and iOS 26.5 in CI.
It needs Xcode 26 or later: the code runs on
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

## Unit tests

`WalletTests/`: 35 XCTest tests of the app's logic, in the simulator, the same cases as the Android
app's unit tests (`android/app/src/test/`). The shared scheme `Wallet` runs them with `TZ=Asia/Taipei`.

```bash
xcodebuild test -project ios/Wallet.xcodeproj -scheme Wallet -derivedDataPath ios/build \
    -destination 'platform=iOS Simulator,name=iPhone 17'               # about 3 s once built
```

| Tests | What they hold the app to |
|---|---|
| `MoneyTests` (8) | Grouping, the typographic minus, integer cents, the 12-digit limit; `[0-9]`, not `\d`: in the simulator's ICU, `\d` takes `１００` |
| `FormatsTests` (5) | Times in the device's time zone, Today and Yesterday by the local date, masked wallet IDs |
| `AttemptTests` (11) | One key per attempt, resent after no answer, a new one for a new amount, none for top-ups, a restored attempt (K-08), and a second submit while one is in flight sends nothing (K-02), which no UI test can reach (SPEC §9) |
| `MessagesSpecParityTests` (2) | Every error text equals SPEC.md §6.6, read from the file |
| `DesignTokenParityTests` (4) | Colours, spacing, radii and text styles equal `web/src/tokens.css` |
| `ApiConfigTests` (5) | The launch argument, ignored in Release builds and when it is not an http(s) URL |

SPEC.md and tokens.css are copied into the test bundle on every build (the group *Shared files*):
read from the Mac's `~/Documents` inside the simulator, the test hung. Each class was seen to fail with
one line of the app broken (SPEC §11, 2.17).

## Project

`Wallet.xcodeproj` is written by hand and small: `Wallet/` and `WalletTests/` are synchronised groups,
so a new Swift file needs no change to the project file.

```
ios/
├── Wallet.xcodeproj/
├── Info.plist                 Merged with Xcode's generated keys: local HTTP, the Inter fonts
├── WalletTests/               Unit tests (XCTest), one file per class above
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
  names, copied from the Android app's `DesignTokens.kt`. Since SPEC 2.17, `DesignTokenParityTests`
  (above) reads `web/src/tokens.css` and fails if any colour, spacing value, radius or text style
  differs, as Android's `DesignTokenParityTest` does.
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
