# test-automation-lab

[![CI](https://github.com/benson-code/test-automation-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/benson-code/test-automation-lab/actions/workflows/ci.yml)

> **Self-built practice project, not production work.** The wallet/payment API under test was written
> for this project as a target for testing. It is not connected to any real payment system.

A pytest suite for a small wallet/payment API, focused on the failures that cost money in payment
systems: **double charges on retry, overdrafts under concurrency, refunds that exceed the original
payment, rounding errors, and half-completed transfers.**

A **mobile web front end** (React) is served by the same API, and **Playwright for Python** tests it
in the same pytest suite: 18 cases in three browser engines (Chromium, WebKit, Firefox), checked
against the database as well as the page. A native **Android app** (Kotlin, Jetpack Compose) has the
same screens and rules, and **Appium** tests it in the same suite, through a test proxy that can hold
a request or lose its response. A native **iOS app** (SwiftUI) has the same screens and rules too, with
fifteen Appium (XCUITest) cases and 35 unit tests on the iOS simulator, run in CI on GitHub's macOS
runner.

The main flows are also provided as a **Postman collection** for manual use, run by **Newman** in CI.
A **k6** load test, followed by a database reconciliation, can be triggered on demand.

**Six defects are planted in the API behind switches. On every push to main, CI turns each one on and
requires the tests assigned to it to fail.** A test that has never been seen to fail is not
evidence that it checks anything. Rules that exist only in the web page cannot be broken by a server
switch, so for those CI changes the page's code instead and requires the matching case to fail.

| Risk | Representative cases | Planted defect (these tests must fail when it is on) |
|---|---|---|
| A retry after a network timeout charges twice | IDM-001, CON-002, WEB-008 | `no_idempotency`: the Idempotency-Key is ignored |
| Concurrent payments overdraw the wallet | CON-001, DB-001 | `race`: no lock around the balance update |
| Partial refunds add up to more than the payment | REF-002, CON-003, WEB-009 | `refund_overflow`: only the individual refund is checked |
| A negative payment credits the payer | VAL-P08, VAL-T08, WEB-005 | `negative_amount`: negative amounts are accepted |
| Floating-point arithmetic loses a cent | PRC-005, WEB-004 | `float_math`: 19.99 × 100 = 1998.9999… |
| A transfer debits the sender but never credits the receiver | TRF-006, DB-001 | `transfer_not_atomic`: debit and credit run in separate transactions |

The same screens on every client. The server took the payment but its answer was lost; the user
retries, and the retry is recognised instead of charged again:

<table>
<tr><th></th><th>Home</th><th>No answer: retrying is safe</th><th>The retry: not charged again</th></tr>
<tr><th>Web</th><td><img src="docs/screenshots/web-home.png" width="180" alt="web-home"></td><td><img src="docs/screenshots/web-no-answer.png" width="180" alt="web-no-answer"></td><td><img src="docs/screenshots/web-replayed.png" width="180" alt="web-replayed"></td></tr>
<tr><th>Android</th><td><img src="docs/screenshots/app-home.png" width="180" alt="app-home"></td><td><img src="docs/screenshots/app-no-answer.png" width="180" alt="app-no-answer"></td><td><img src="docs/screenshots/app-replayed.png" width="180" alt="app-replayed"></td></tr>
<tr><th>iOS</th><td><img src="docs/screenshots/ios-home.png" width="180" alt="ios-home"></td><td><img src="docs/screenshots/ios-no-answer.png" width="180" alt="ios-no-answer"></td><td><img src="docs/screenshots/ios-replayed.png" width="180" alt="ios-replayed"></td></tr>
</table>

---

## Contents

1. [Architecture](#1-architecture)
2. [System under test](#2-system-under-test)
3. [Test strategy](#3-test-strategy)
4. [Web front end, Android and iOS apps, UI tests](#4-web-front-end-android-and-ios-apps-ui-tests)
5. [Postman and Newman](#5-postman-and-newman)
6. [Load testing (k6)](#6-load-testing-k6)
7. [Running locally](#7-running-locally)
8. [CI](#8-ci)
9. [AI-assisted development](#9-ai-assisted-development)
10. [Issues found during development](#10-issues-found-during-development)

---

## 1. Architecture

```
test-automation-lab/
├── app/                       System under test: FastAPI + SQLite
│   ├── main.py                HTTP routes, uniform error format
│   ├── service.py             Business rules (payments, refunds, transfers, idempotency)
│   ├── money.py               Amounts: string <-> integer cents
│   ├── db.py                  Schema, transactions (BEGIN IMMEDIATE)
│   └── bugs.py                Planted-defect switches
├── framework/                 (1) API client layer
│   ├── base_client.py         BaseClient: base URL, timeout, request logging
│   ├── wallet_api.py          One method per endpoint
│   ├── db.py                  Direct SQLite access: data seeding, seven database invariants
│   ├── web/                   Web page objects (one per screen) and network control: hold, lose, block
│   ├── app/                   App screen objects, adb device control, and the test proxy: hold, lose, block
│   └── ios/                   iOS screen objects and simulator control (simctl); the test proxy is app/'s
├── testdata/                  (2) Test data layer
│   ├── schemas/*.json         JSON Schemas for every response type
│   ├── schema.py              Validation that reports every mismatching field
│   ├── factories.py           Factory functions for wallets and payments
│   ├── cases.py               CSV loader; case_id, marks and is_run live in the data
│   └── messages.py            Expected error texts for every client, copied from SPEC.md
├── cases/
│   └── amount_validation.csv  Amount-format cases (34, one per row)
├── tests/                     (3) Test case layer
│   ├── conftest.py            API startup, fixtures, --env / --target_case_ids / --target_marks
│   ├── test_*.py              100 API tests
│   ├── web/                   78 web UI test runs (Playwright): three engines, failure evidence
│   ├── app/                   58 app UI test runs (Appium): device, displays, test proxy, failure evidence
│   └── ios/                   20 iOS UI test runs (Appium XCUITest): simulator, test proxy, failure evidence
├── SPEC.md                    Specification for the clients (web, Android, iOS): rules, screens, hooks, cases
├── android/                   Native Android app: Kotlin + Jetpack Compose
├── ios/                       Native iOS app: Swift + SwiftUI
├── web/                       Mobile web front end: React + Vite, served by the API under /app
│   └── src/                   tokens.css (Figma variables), components/ (one per Figma component), screens/
├── postman/                   Postman collection (run by Newman in CI)
│   ├── payment-api.postman_collection.json
│   ├── local.postman_environment.json
│   ├── data/amount-boundaries.csv   Data-driven amount boundaries
│   └── run-newman.sh          Start the API, run Newman, write reports
├── load/                      k6 load test (run in CI only)
│   ├── payments.js            smoke / load / stress scenarios
│   ├── run-load.sh            Start the API, run k6, reconcile the database
│   └── README.md              Test types, threshold rationale, measured results
├── tools/
│   ├── fault_check.py         Turns on each planted defect and checks the named pytest tests fail (--app, --ios: app cases)
│   ├── web_mutation_check.py  Breaks one piece of the web page and checks the named web case fails
│   ├── newman_fault_check.py  The same check for the Postman collection
│   ├── check_invariants.py    Reconciliation: runs every invariant against a database (after load tests)
│   ├── parity_check.py        The same inputs through the web page and the app; reports any difference
│   ├── demo.py                A clean API with a demo wallet, for showing the clients
│   └── screenshots.py         The README screenshots, web and apps, from the same demo data
├── docs/screenshots/          Web and app screens for this README (generated)
└── .github/workflows/         ci.yml (push to main, pull requests), load.yml (manual)
```

**Why three layers:** test cases state only what is done and what is expected; they do not deal with
URLs or headers. A change to an API path touches only the client layer, and a new amount format is a
single CSV row.

Code comments, test docstrings, Postman request names and the k6 run summary are written in
Traditional Chinese; the web front end (`web/`) is written in English.

## 2. System under test

| Method | Path | Description |
|---|---|---|
| POST | `/wallets` | Create a wallet |
| POST | `/wallets/{id}/topups` | Top up a wallet |
| GET | `/wallets/{id}` | Get the balance |
| GET | `/wallets/{id}/transactions` | Transaction history (ledger) |
| POST | `/payments` | Pay; requires an `Idempotency-Key` header |
| GET | `/payments/{id}` | Payment details, including refunds |
| POST | `/payments/{id}/refunds` | Refund, fully or in several partial refunds; requires an `Idempotency-Key` header |
| POST | `/transfers` | Transfer between wallets; requires an `Idempotency-Key` header |
| GET | `/health` | Health check, including which planted defects are switched on |

**Design decisions**

1. **Amounts travel as strings and are stored as integer cents.** `"100.50"` is stored as `10050`.
   JSON numbers are commonly parsed into floating-point values, and in floating point
   `0.1 + 0.2 = 0.30000000000000004`. Amounts have at most two decimal places; the minimum is `0.01`.
2. **Every balance change goes through a single function, which also writes a ledger entry.**
   The rule "a wallet's balance equals the sum of its ledger entries" therefore always holds,
   and the tests verify it directly in SQL.
3. **Every write runs inside a `BEGIN IMMEDIATE` transaction.** Looking up the Idempotency-Key,
   debiting the wallet and storing the key happen under one lock, so when two requests arrive with
   the same key, the second one waits and then finds the first one's result. If the debit fails,
   the whole transaction is rolled back and the key is not stored, so the client can retry with the
   same key after topping up.

Every error response has the form `{"error_code": "...", "message": "..."}`.

The API document (OpenAPI) is served at `/docs` (Swagger UI) and `/openapi.json`. Each route declares
its real responses and error codes; CTR-004 checks that the document and the API agree.

## 3. Test strategy

There are 100 API tests (the web and app UI tests are described in section 4). Each group starts from the
question "if this breaks, what happens to the money?"

| File | Tests | What it guards against |
|---|---|---|
| `test_smoke.py` | 2 | Run first after a deployment: the service is up and the main money flow works. With the tests in other files marked `smoke`, the smoke set has 4 tests |
| `test_validation.py` | 44 | 34 from the CSV: zero, negative, more than two decimal places, scientific notation, a number instead of a string, whitespace, null, boolean, digits from other scripts (`１００`, `٣٠`). Also Idempotency-Key, wallet and owner validation |
| `test_business.py` | 8 | Paying exactly the balance and one cent more; a failed payment leaves no trace; the single-payment limit at 49,999.99 / 50,000.00 / 50,000.01 |
| `test_precision.py` | 8 | 0.10 + 0.20; refunds of 33.33 + 33.33 + 33.34 return every cent; the last remaining cent; values such as 19.99 that floating point gets wrong |
| `test_idempotency.py` | 7 | A retry with the same key charges once; the same key with a different body is rejected; different keys are two legitimate purchases; refund and transfer retries |
| `test_concurrency.py` | 4 | 10 simultaneous payments never overdraw; 10 simultaneous retries with one key charge once; simultaneous refunds never exceed the payment; opposing transfers |
| `test_refund.py` | 10 | Cumulative limit, a single refund above the payment, invalid amounts, unknown payments, refund details |
| `test_transfer.py` | 5 | Debit and credit happen together or not at all; unknown receiver; transfer to oneself; limit |
| `test_contract.py` | 4 | Every success and error response is validated against a JSON Schema that allows no extra fields. The API's own document (`/openapi.json`, shown at `/docs`) must list exactly the statuses the API answers with, each in the format it describes |
| `test_db_invariants.py` | 8 | Seven SQL queries that must return no rows, plus a test proving each query can detect a violation |

**Principles**

- **Assertions go beyond the HTTP response.** A retry test does not stop at the second response; it
  queries the `payments` table and confirms there is exactly one row. The API reporting no double
  charge is not proof; a single row in the database is.
- **Start from a valid request and change one field at a time.** If two fields change and the request
  is rejected, the cause is ambiguous.
- **Boundaries are tested at three points:** the last valid value, the boundary itself, and the first
  invalid value.
- **Concurrency tests check correctness, not performance.** Each case sends 5 to 20 requests and
  finishes within a second. Performance is covered separately by the load test (section 6).
- **A query that never returns rows may simply be wrong.** DB-005 copies the database, corrupts it
  deliberately, and confirms that each of the seven invariant queries detects the corruption.
- **Test data must be verified.** 33.33 was expected to trigger a floating-point error, but
  `33.33 * 100 == 3333.0` exactly; 19.99, 1.15, 0.29 and 4.35 do trigger it. Without the planted
  defect, this mistake in the test data would have gone unnoticed.

**Selecting cases by test data** (as in data-driven frameworks, case_id and marks are part of the data):

```bash
pytest --target_marks=smoke                      # smoke tests only
pytest --target_marks=idempotency,concurrency    # tests with any of these marks
pytest --target_case_ids=CON-001,VAL-P08         # specific cases
```

## 4. Web front end, Android and iOS apps, UI tests

A mobile-first wallet page (React 19 + Vite) in front of the same API, served by FastAPI under
`/app`. It exists so that the risks tested at the API level are also tested where a user meets them:
a double tap, a slow network, a response lost on its way back. There is no login and no transfer
screen. Its specification is [`SPEC.md`](SPEC.md), which also defines the Android app with the
same screens and behaviour (in [`android/`](android/README.md)), and the iOS app, also with the same
screens (in [`ios/`](ios/README.md)). The Appium tests of both apps are described below.

**Screens:** Start (create or open a wallet) · Home and History tabs · Top up · Pay: amount →
Confirm → receipt · Payment detail with refunds.

<details>
<summary>Six screens, web, Android and iOS side by side (the same demo data)</summary>

Web and Android at 360 × 640; iOS on an iPhone 17 simulator, whose screen is longer.

<table>
<tr><th></th><th>Web</th><th>Android</th><th>iOS</th></tr>
<tr><td>Home</td><td><img src="docs/screenshots/web-home.png" width="200" alt="web-home"></td><td><img src="docs/screenshots/app-home.png" width="200" alt="app-home"></td><td><img src="docs/screenshots/ios-home.png" width="200" alt="ios-home"></td></tr>
<tr><td>History</td><td><img src="docs/screenshots/web-history.png" width="200" alt="web-history"></td><td><img src="docs/screenshots/app-history.png" width="200" alt="app-history"></td><td><img src="docs/screenshots/ios-history.png" width="200" alt="ios-history"></td></tr>
<tr><td>Payment detail, partly refunded</td><td><img src="docs/screenshots/web-payment.png" width="200" alt="web-payment"></td><td><img src="docs/screenshots/app-payment.png" width="200" alt="app-payment"></td><td><img src="docs/screenshots/ios-payment.png" width="200" alt="ios-payment"></td></tr>
<tr><td>Confirm</td><td><img src="docs/screenshots/web-confirm.png" width="200" alt="web-confirm"></td><td><img src="docs/screenshots/app-confirm.png" width="200" alt="app-confirm"></td><td><img src="docs/screenshots/ios-confirm.png" width="200" alt="ios-confirm"></td></tr>
<tr><td>No answer</td><td><img src="docs/screenshots/web-no-answer.png" width="200" alt="web-no-answer"></td><td><img src="docs/screenshots/app-no-answer.png" width="200" alt="app-no-answer"></td><td><img src="docs/screenshots/ios-no-answer.png" width="200" alt="ios-no-answer"></td></tr>
<tr><td>Receipt after the retry</td><td><img src="docs/screenshots/web-replayed.png" width="200" alt="web-replayed"></td><td><img src="docs/screenshots/app-replayed.png" width="200" alt="app-replayed"></td><td><img src="docs/screenshots/ios-replayed.png" width="200" alt="ios-replayed"></td></tr>
</table>

Generated by `tools/screenshots.py`; run it again after changing a screen.
</details>

**Design.** The visual design is a design system in a Figma file (private): 25 colour variables
over 18 primitives, spacing and radius variables, eight text styles and ten components, most of
them with variants. The screens are built in code from it. The Figma file has no screen frames; SPEC.md §7
lists each screen's states and test hooks instead.

- `web/src/tokens.css` declares every Figma variable under the name of its code syntax in Figma:
  `color/bg/page` becomes `var(--color-bg-page)`.
- Each Figma component has one React component of the same name (`TopBar`, `AmountField`,
  `TransactionRow`, ...).

**Specification.** SPEC.md numbers every rule (input `R`, Idempotency-Key attempts `K`, navigation
`N`, display `D`, layout `L`, error messages `E`) and traces each rule to the cases that cover it,
including the rules no case covers yet (none of those can move money). Before the specification was
published, its web rules were checked against the running page with a browser script; the two that
cannot be checked that way are marked as checked by reading the code.

**Idempotency in the page.** One Idempotency-Key is created per payment attempt, when *Confirm
payment* is tapped. After no answer, the attempt is kept: *Retry*, or going back and continuing with
the same amount, resends the same key, so a payment that did go through is returned instead of
charged again. Only a different amount starts a new attempt. While a request is in flight, a
second tap sends nothing.

### UI tests

Playwright for Python, in the same pytest suite as the API tests. The web tests reuse the API's
server, `api` and `db` fixtures, its marks and its `--target_case_ids` / `--target_marks` selection:
`--target_marks=precision` selects the API and the UI precision tests together.

- **Cross-browser.** Every case runs three times, each in the engine of its profile: Pixel 7 in
  Chromium (Chrome's engine), iPhone 14 in WebKit (Safari's engine) and a desktop in Firefox. WebKit
  here is Playwright's Linux build of Safari's engine, not Safari on iOS. The time zone is pinned.
- Setup goes through the API; only the behaviour under test goes through the page.
- Every case except the layout check (WEB-011) checks the database as well as the page, and every
  case fails on any uncaught JavaScript error.
- Elements are found by `data-testid` only (SPEC.md §7). Expected texts are copied from the
  specification (`testdata/messages.py`), not read from the front end's own code.
- A failure leaves a screenshot and a Playwright trace in `reports/web/`; CI uploads them.
- Accessibility is checked on every change: WEB-015 runs **axe-core** (WCAG 2.2 A and AA) on 17 states
  of the page, WEB-016 moves through every screen with the keyboard. Neither replaces listening with
  VoiceOver or TalkBack (SPEC.md §10).

| Case | What it checks | Proven to fail by |
|---|---|---|
| WEB-001 | A new wallet starts at 0.00 | |
| WEB-002 | A top-up reaches the balance and the ledger | |
| WEB-003 | Pay through Confirm to the receipt and History; one UUID v4 key, sent only on Confirm | |
| WEB-004 | A top-up of 19.99 keeps every cent | `float_math` |
| WEB-005 | `-1`, `1e3`, `10.555`, ` 5 ` and amounts of 13 and 20 digits are shown as typed on Confirm and refused; nothing moves | `negative_amount` |
| WEB-006 | A payment above the balance is refused; *Change amount* keeps the input | |
| WEB-007 | Two taps in the same instant send one payment | mutation `no_in_flight_guard` |
| WEB-008 | The server charges, the response is lost, the user retries: same key, "already gone through", one payment | `no_idempotency` |
| WEB-009 | A partial refund, then the cumulative refund limit | `refund_overflow` |
| WEB-010 | History equals the ledger, row by row | |
| WEB-011 | Eight screens: no horizontal scrolling, every button and link at least 44 × 44 px | |
| WEB-012 | While processing, Confirm, Cancel and Back are disabled | mutation `confirm_stays_enabled` |
| WEB-013 | Back after no answer: the same amount keeps the key, a new amount gets a new one | mutation `back_forgets_the_attempt` |
| WEB-014 | No Retry after a top-up gets no answer (the API takes no key for top-ups) | mutation `top_up_offers_retry` |
| WEB-015 | 17 states pass axe-core's WCAG 2.2 A and AA rules; every input has a visible label | mutations `balance_toggle_unnamed`, `amount_label_detached` |
| WEB-016 | Tab and Shift+Tab through every screen: focus is never entirely behind the top bar or tab bar | mutation `no_scroll_padding` |
| WEB-017 | Amounts are drawn in tabular figures on every screen, measured in the browser: ten 1s as wide as ten 0s | the defect itself (the build before 2.11) |
| WEB-018 | A card's hairline takes no room: every card's first child starts exactly the card's padding below its top, as in the apps | the defect itself (the build before 2.16) |

**Simulating the network.** `framework/web/network.py` uses Playwright's request interception; the
API is not changed.

- `hold`: the request waits in the browser until it is released (processing state, double tap).
- `lose_response`: the request reaches the server and is processed, but the browser sees a dropped
  connection. This is the case that makes reusing the key necessary: the money has moved, and the
  user only knows that there was no answer.
- `block`: the request never leaves the browser.

**Proving the UI tests can fail.** Two mechanisms, both run by CI:

1. **Planted server defects.** `tools/fault_check.py` also requires the web cases in the table to
   fail, in all three engines.
2. **Rules that live only in the page.** No server switch can break the in-flight guard, the disabled
   button, the pending attempt, the missing Retry, an accessible name, a label or the scroll padding. `tools/web_mutation_check.py` changes one piece
   of the page's code, builds that version, serves it to the tests (through the `WEB_DIST`
   environment variable) and requires the matching case to fail in every engine: a mutation caught in
   Chromium but not in WebKit would be a problem Safari users could meet unnoticed. All seven
   mutations are caught in all three engines.

**Running**

```bash
(cd web && npm ci && npm run build)        # the API serves /app only once web/dist exists
.venv/bin/pip install -r requirements-web.txt
.venv/bin/python -m playwright install chromium webkit firefox
sudo .venv/bin/python -m playwright install-deps webkit   # once: the libraries WebKit needs on Linux

.venv/bin/pytest tests/web                       # 78 runs, 30 to 90 seconds
.venv/bin/python tools/fault_check.py --web-only # planted defects, web cases only
.venv/bin/python tools/web_mutation_check.py     # page mutations; needs Node on PATH
```

Without Playwright, `tests/web` is skipped and pytest prints why. With Playwright but no build,
every web test fails with "Build it first", so a run in which nothing was tested cannot look like a
pass.

### Android app UI tests

Appium (UiAutomator2) for Python, in the same pytest suite again: the app tests reuse the API's
server, `api` and `db` fixtures and the case selection, and each case mirrors a web case (APP-001
tests what WEB-001 tests).

- Every case runs in two display configurations of one device, 360 × 640 dp and 411 × 914 dp
  (`wm size` and `wm density`, restored afterwards). The time zone is pinned.
- **A test proxy instead of request interception.** A native app cannot be intercepted the way a
  browser can, so the debug build is launched with its API address pointing at
  `framework/app/proxy.py`, which forwards every request to the API and records its
  Idempotency-Key. On demand it holds a request, loses its response or blocks it: the same three
  conditions as the web tests. It listens on 127.0.0.1 only; the device reaches it through
  `adb reverse`.
- Each test starts the app fresh (`am start -S`), opens a wallet prepared through the API, and
  checks the database as well as the screen. A test fails if the app crashed; a failure leaves a
  screenshot and the UI tree in `reports/app/`.
- Elements are found by the same hook names as on the web (Compose `testTag`, exposed as resource
  IDs). Expected texts come from the same `testdata/messages.py`.

| Case | What it checks | Proven to fail by |
|---|---|---|
| APP-001 | A new wallet starts at 0.00. The screen shows the wallet ID masked; the test takes the full ID from the answer the proxy recorded | |
| APP-002 | A top-up reaches the balance and the ledger | |
| APP-003 | Pay through Confirm to the receipt and History; one UUID v4 key, sent only on Confirm | |
| APP-004 | A top-up of 19.99 keeps every cent | `float_math` |
| APP-005 | `-1`, `1e3`, `10.555`, ` 5 ` and amounts of 13 and 20 digits are shown as typed on Confirm, without a balance after, and refused; nothing moves | `negative_amount` (`-1`); the 20 digits crashed the app before 2.11 |
| APP-006 | A payment above the balance is refused; *Change amount* keeps the input | |
| APP-007 | A double tap on Confirm sends one payment | see below |
| APP-008 | The server charges, the response is lost, the user retries: same key, "already gone through", one payment | `no_idempotency` |
| APP-009 | A partial refund, then the cumulative refund limit (the payment is opened from History: the app has no URLs) | `refund_overflow` |
| APP-010 | History equals the ledger, row by row, also when it is longer than the screen | |
| APP-011 | Every screen in both displays, also with a 50-character name and the largest balance: nothing off screen, overlapping or squeezed, every part of every row visible, touch targets at least 48 dp; messages after an action in view | by hand |
| APP-012 | While processing, Confirm reads *Processing…* and Confirm, Cancel and Back are disabled | by hand |
| APP-013 | Back after no answer: the same amount keeps the key, a new amount gets a new one | by hand |
| APP-014 | No Retry after a top-up gets no answer, and the top-up carried no key | by hand |
| APP-015 | The app's process is killed while the outcome is unknown: reopened, it shows Confirm with "no answer", and Retry resends the saved key | `no_idempotency` |
| APP-016 | System Back: on Confirm it keeps the pending attempt, while processing it does nothing, on the receipt it goes Home | by hand |
| APP-017 | The process is killed on the receipt: reopened, the same receipt, never Confirm (the double charge found in the QA pass) | by hand |

**Proving the app tests can fail.** `tools/fault_check.py --app` requires the cases with a planted
defect in the last column to fail under it, in both displays. The cases marked *by hand* test rules
that live only in the app, which no server switch can break: each was seen to fail with one change
to the app's code, built and run on redroid (SPEC.md §9 lists the changes). One did not:
with the in-flight guard removed, APP-007 still passes, because UiAutomator waits for each injected
event to be handled and the second tap arrives after the button has been redrawn disabled. The
guard is proven by the app's unit test, which fails without it.

**What the layout check can and cannot see.** Android drops a text squeezed to zero width from the
accessibility tree, even with UiAutomator2's `allowInvisibleElements`. The two layout defects of the
QA pass (*From* crushed by a long name, *TWD* stacked next to a long balance) were drawn on screen and
absent from every element list, so no check of element bounds could find them. The rows now carry
hooks (`receipt-row`, `balance-row`), and APP-011 requires every part of every row to be visible; the
web applies the same rule.

**The web and the Android app side by side.** `tools/parity_check.py` sends the same 44 inputs (payment, top-up and
refund amounts, valid and invalid) through the page and through the app, each from a fresh wallet,
and compares what each showed (whether the button was enabled, Confirm's amount and balance after,
the receipt or the message) and what the server did. Its first version, run during the QA pass,
found the API accepting `１００`.

**Running**

```bash
.venv/bin/pip install -r requirements-app.txt
(cd android && ./gradlew assembleDebug)          # the debug build: only it accepts the proxy's address
appium --address 127.0.0.1 --port 4723           # Appium 3 and the uiautomator2 driver, another terminal
export ANDROID_SERIAL=127.0.0.1:5555                      # the device, when adb sees more than one
.venv/bin/pytest tests/app --app                          # 58 runs, 5 to 10 minutes (devices below)
.venv/bin/python tools/fault_check.py --app-only          # planted defects, app cases only
.venv/bin/python tools/parity_check.py                    # web and app compared; needs the web build too
```

The app tests need a device, so they are collected only with `--app`; without it, pytest's header
says so. With `--app` but no device, no Appium server or no APK, every app test fails and says what
is missing.

**Devices.** The suite has been run on two kinds of device, with the same code and the same results:

| Device | Android | Host | `ANDROID_SERIAL` | Time for the suite |
|---|---|---|---|---|
| redroid: Android in a Docker container | 14 | The ARM64 Linux development machine (section 7) | `127.0.0.1:5555` | about 8 minutes (54 runs) |
| Google's Android Emulator: Pixel 7 profile, arm64 image | 16 (API 36, the app's target) | A Mac with Apple silicon | `emulator-5554` | about 5 minutes (54 runs) |
| Google's Android Emulator: Pixel 7 profile, x86-64 image | 16 (API 36) | GitHub's x64 Linux runner, in CI (section 8) | `emulator-5554` | 7 to 10 minutes (58 runs) |

redroid shares the host's Linux kernel and needs its binder driver, so it runs on Linux only. The
emulator is a virtual machine with its own kernel (on a Mac, through Apple's Hypervisor framework),
so it runs on macOS without Docker. On the emulator, `tools/fault_check.py --app-only` also catches
all four planted defects that have app cases.

Setting up the emulator on a Mac with the SDK's command-line tools; Android Studio is not needed:

```bash
export ANDROID_HOME=~/Library/Android/sdk   # command-line tools unpacked in $ANDROID_HOME/cmdline-tools/latest
yes | sdkmanager --licenses
sdkmanager "platform-tools" "emulator" "platforms;android-36" "system-images;android-36;google_apis;arm64-v8a"
avdmanager create avd -n pixel7-api36 -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_7
emulator -avd pixel7-api36 -no-window -no-audio > emulator.log 2>&1 &   # output to a file: see below
export ANDROID_SERIAL=emulator-5554
(cd android && JAVA_HOME=/path/to/jdk-21 ./gradlew assembleDebug)       # Gradle 8.14 does not run on JDK 25
```

Send the emulator's output to a file. In the first runs on the Mac it was piped into a command that
had already exited, and adb lost the device now and then (`device offline`) while Appium was starting
a session. Started with its output going to a file, the emulator did not drop again: six sessions in
a row, the 54 runs and the defect check.

### iOS app UI tests

Appium for Python with the XCUITest driver, in the same pytest suite: the iOS tests reuse the API's
server, `api` and `db` fixtures, the case selection and the Android tests' test proxy. Each case mirrors
the Android and web cases with the same number (IOS-008 tests what APP-008 and WEB-008 test). The app
([`ios/`](ios/README.md), SwiftUI) has every screen since version 2.14 of the specification.

- **No forwarding.** The iOS simulator shares the Mac's network, so the debug build, launched with
  `-apiBaseUrl`, reaches the test proxy on 127.0.0.1 directly. Android needs `adb reverse` for this.
- Each test starts the app fresh (`terminate_app`, the screen state iOS saved deleted, then
  `simctl launch --terminate-running-process` with the launch argument and a pinned time zone, and a
  check of the app's own command line that the argument is there), opens a wallet prepared through
  the API, and checks the database as well as the screen. A test fails if the app is no longer running in the
  foreground at the end; a failure leaves a screenshot and the UI tree in `reports/ios/`.
- Elements are found by the same hook names, as accessibility ids (SwiftUI `accessibilityIdentifier`),
  and expected texts come from the same `testdata/messages.py`.
- **No scrolling to read a list.** XCUITest sees the rows outside the visible part of a scroll view, so
  History is read in one pass; on Android, UiAutomator sees only what is on the screen, and the tests
  scroll and join.

| Case | What it checks | Proven to fail by |
|---|---|---|
| IOS-001 | A new wallet starts at 0.00; the full wallet ID comes from the answer the proxy recorded | |
| IOS-002 | A top-up of 100 reaches the receipt, Home's balance and the ledger | |
| IOS-003 | Pay through Confirm to the receipt, then History's first row `−30.00`; one UUID v4 key, sent only on Confirm | |
| IOS-004 | A top-up of 19.99 keeps every cent | `float_math` |
| IOS-005 | `10.555` and amounts of 13 and 20 digits are shown as typed on Confirm and refused; nothing moves | the 13 digits, on the build before 2.11 |
| IOS-006 | A payment above the balance is refused; *Change amount* keeps the input | |
| IOS-008 | The server charges, the response is lost, the user retries: same key, "already gone through", one payment | `no_idempotency`; by hand: the app sending a new key on Retry |
| IOS-009 | Refund 10 of a payment of 30, opened from History; then 25 is refused, since only 20 is left | `refund_overflow` |
| IOS-010 | Every History row matches the ledger: order, type, amount and balance after, also with 12 entries | |
| IOS-014 | A top-up that gets no answer offers no Retry and sends no key; the user is asked to check the balance | |
| IOS-015 | A payment gets no answer; the app goes to the background and its process is killed, as iOS does to free memory. Reopened: Confirm with *no answer*, and Retry resends the saved key; one payment | `no_idempotency`; the app before 2.15 (it reopened on Start) |
| IOS-017 | The same on the receipt, and on a replayed receipt: reopened, the same receipt and no *Confirm payment* | the app before 2.15; by hand: the receipt left out of the saved state, which reopened on Confirm and took a second payment |
| IOS-018 | The text styles keep their line heights: ledger rows 67 pt apart and receipt rows 47, as on the web and Android; six History rows exactly 5 × 67 | the build before 2.12 (61 and 43); the build before 2.16 (338 for 335) |
| IOS-019 | Amounts are in tabular figures: amounts made of 1s are as wide as the same amounts made of 0s, on Confirm, the receipt and Home | the build before 2.13 (*Balance after*, 43 against 62 pt) |
| IOS-020 | Icons take their 24 pt box: a message's text starts 72 pt from the edge, the receipt heading 52, as on the web and Android | the build before 2.16 (67 and 47) |

**Running** (macOS with Xcode 26 or later, Appium 3 with the xcuitest driver):

```bash
.venv/bin/pip install -r requirements-app.txt
xcodebuild -project ios/Wallet.xcodeproj -scheme Wallet -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath ios/build build
xcrun simctl boot "iPhone 17"                    # any iPhone simulator: one booted, or choose with IOS_UDID
appium --address 127.0.0.1 --port 4723           # another terminal (appium driver install xcuitest, once)
.venv/bin/pytest tests/ios --ios                 # 15 cases in 20 runs, about 155 seconds
.venv/bin/python tools/fault_check.py --ios-only # planted defects, iOS cases only
xcodebuild test -project ios/Wallet.xcodeproj -scheme Wallet -derivedDataPath ios/build \
    -destination 'platform=iOS Simulator,name=iPhone 17'   # the app's 35 unit tests, about 3 seconds
```

On an iPhone 17 simulator (iOS 26, Xcode 27) the four cases passed three runs in a row, about 27
seconds each; with IOS-005, 018 and 019 (versions 2.11 to 2.13), the 9 runs passed three times in a
row, about 69 seconds each; with the second stage's five cases (2.14), the 15 runs passed three times
in a row, about 107 seconds each; with K-08's two cases (2.15), the 18 runs passed three times in a row,
about 142 seconds each; with IOS-020 and IOS-018's second test (2.16), the 20 runs passed three
times in a row, about 156 seconds each. The first session on a simulator also builds WebDriverAgent, which takes a
few minutes once.
Like the Android tests, they are collected only with `--ios`; with `--ios` but no simulator, Appium
server or app build, every test fails and says what is missing.

**Next stages.** Every screen is done (2.14), K-08 (2.15), the three clients measured again (2.16) and
the unit tests (2.17), and all of it in CI on macOS (2.18). Still to come: cases across clients: for example a payment made in the Android app, seen in the web page's History and
refunded in the iOS app, with the database reconciled after each step.

## 5. Postman and Newman

`postman/` holds a Postman collection for the same API. It can be imported into Postman for manual
use, and Newman runs it from the command line and in CI.

**Division of work with pytest**

| | Postman / Newman | pytest |
|---|---|---|
| Purpose | Lets developers and product managers reproduce issues by importing it; exploratory testing; handover | Primary automated regression suite |
| Coverage | Main flows and representative errors (25 requests), plus amount boundaries (9 CSV rows) | 100 API tests |
| Cannot do | Query the database; generate concurrency (one request at a time) | — |

**Collection structure**

| Folder | Cases | Focus |
|---|---|---|
| 01 Health check | PM-01 | Confirms no planted defect is switched on |
| 02 Main flow | PM-02–08 | Create a wallet, top up, pay, refund, reconcile; each request passes saved IDs to the next |
| 03 Idempotency | PM-09–12 | A retry with the same key charges once: the response is marked `Idempotent-Replayed: true` and the balance is unchanged |
| 04 Error handling | PM-13–18 | Insufficient balance by one cent, cumulative over-refund, amount sent as a number, single-payment limit exceeded |
| 05 Transfers | PM-19–25 | After a failed transfer, the balance is read again to confirm nothing was debited |
| 06 Amount boundaries | AMT-01–09 | Reads `postman/data/amount-boundaries.csv` and runs once per row |

Every request also runs collection-level checks: response time under 1 second, a JSON response, and
the uniform error format for error responses. Every test name starts with its case ID, so report
entries map directly to cases.

**Running**

```bash
npm install -g newman@6.2.2 newman-reporter-htmlextra@1.23.1

postman/run-newman.sh                                  # starts its own API (temporary database) and stops it afterwards
BASE_URL=http://127.0.0.1:8400 postman/run-newman.sh   # targets an API that is already running
.venv/bin/python tools/newman_fault_check.py           # proves the collection catches the planted defects
```

Reports are written to `reports/newman/`: `main.html` and `amounts.html` (htmlextra) and JUnit XML.

In Postman, import the collection and the `local` environment; the whole collection can then be run
directly (folder 06 skips itself when no data file is supplied). To run folder 06, select only that
folder in the Collection Runner and choose the CSV file above.

**The collection must also prove that it catches defects**

| Planted defect | Cases that must fail |
|---|---|
| `no_idempotency` | PM-09, PM-10, PM-11 |
| `refund_overflow` | PM-15 |
| `negative_amount` | AMT-05, AMT-06 |
| `float_math` | AMT-03, AMT-04 |
| `transfer_not_atomic` | PM-25 |
| `race` | Excluded: Postman cannot generate concurrency, so this is left to pytest |

With `transfer_not_atomic` on, PM-24 (transfer to a non-existent wallet) still returns 404, so the
status code alone suggests nothing is wrong. Only PM-25, which reads the balance again, detects the
missing money.

## 6. Load testing (k6)

`load/payments.js` sends 80% payments and 20% balance reads; 10% of payments are retried with the same
Idempotency-Key. An arrival-rate executor holds the number of requests per second constant, so the
load does not ease off when the server slows down.

- **load**: 20 requests per second for 1 minute. Thresholds: error rate below 1%, payment p95 below
  500 ms, balance-read p95 below 300 ms.
- **stress**: ramps from 20 to 400 requests per second and stops if a threshold breaks, reporting the
  load at that point. On the CI runner, the run completed every stage without breaking a threshold
  (payment p95 of 4 ms up to 400 requests per second), so the limit was not found. `load/README.md`
  explains why the load was not raised further.

**Every run ends with a reconciliation.** `tools/check_invariants.py` checks eight rules against the
load-test database and fails the run if any rule is broken, in every scenario: a stress run may break
its thresholds, but never the balances. One rule was added because of the load test, "every payment
has a matching Idempotency-Key": when payments are duplicated, the books still balance (each payment
has its own ledger entry), so the original seven rules all pass and only this rule detects the problem.

The load test is triggered manually in CI (Actions → Load test). Scenario design, threshold rationale
and measured results are in [`load/README.md`](load/README.md).

## 7. Running locally

The development environment is Ubuntu on an Oracle Cloud ARM64 instance (Ampere A1). The API, the
tests and CI need no Docker; the one exception is the device for the Android app tests on that
machine, redroid, which runs Android in a Docker container (section 4). On a Mac, the app tests run on
Google's emulator instead, without Docker; the iOS app tests need a Mac with Xcode.
Python 3.12 is required; the web front end and its tests also need Node 20 or later (section 4).

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Run every test: starts its own API (random port, temporary database) and stops it afterwards
.venv/bin/pytest

# HTML report
.venv/bin/pytest --html=reports/report.html --self-contained-html

# Prove the tests catch the planted defects (API tests only: about 30 seconds)
.venv/bin/python tools/fault_check.py --api-only
# Without --api-only the web cases are included when the web tests can run (section 4)

# Start the API for manual requests
DB_PATH=wallet.db .venv/bin/uvicorn app.main:app --port 8400
BUGS=race DB_PATH=wallet.db .venv/bin/uvicorn app.main:app --port 8400   # with a planted defect on

# Target an API that is already running (this is how CI runs the suite)
.venv/bin/pytest --env=external --base-url=http://127.0.0.1:8400 --db-path=wallet.db
```

> Pass custom options as `--opt=value`. With `--db-path /tmp/x.db` (separated by a space), pytest
> treats `/tmp/x.db` as a test path before reading its configuration and uses it to determine the
> project root. It then finds neither `pytest.ini` nor `conftest.py`, and every custom option is
> reported as unrecognized.

**Demo.** A clean API with a wallet that already has a history (top-ups, payments, a partial
refund):

```bash
(cd web && npm ci && npm run build)          # once: the page the API serves under /app
.venv/bin/python tools/demo.py               # prints the web URL and the wallet ID; Ctrl+C ends it
.venv/bin/python tools/demo.py --bugs float_math   # the same, with a planted defect on

# A planted defect caught by the UI tests, live (setup in section 4): WEB-004 fails in all three engines
BUGS=float_math .venv/bin/pytest tests/web --target_case_ids=WEB-004
```

The API listens on 127.0.0.1 only. To open the page from another computer, forward a port over
SSH (`ssh -N -L 18400:127.0.0.1:8400 <server>`) and browse to `http://localhost:18400/app/`.

## 8. CI

`.github/workflows/ci.yml` runs seven jobs on every push to `main` and on every pull request:

1. **API tests**: starts the API in the background, waits for `/health`, runs the smoke tests and
   stops if they fail, then runs the full regression suite and uploads the pytest-html and JUnit
   reports (also on failure, so the evidence is kept).
2. **Tests catch planted bugs**: `tools/fault_check.py --api-only` turns on each of the six planted
   defects in turn. Each defect lists the tests that must catch it; if any of them passes, CI fails.
3. **Postman collection (Newman)**: runs the main flows and the CSV amount boundaries, uploads the
   htmlextra and JUnit reports, then runs `tools/newman_fault_check.py`, the same defect check for
   the collection.
4. **Web UI tests (Playwright)**: builds the front end (`npm ci`, Node 22), installs Chromium,
   WebKit and Firefox, runs the web tests in all three and uploads the report together with any failure
   screenshots and traces. It then runs `tools/fault_check.py --web-only` (the planted defects
   against the web cases) and `tools/web_mutation_check.py` (the page mutations).
5. **Android app (build and unit tests)**: builds the debug app on an x86-64 runner and runs its unit
   tests, including a check that the app's design tokens equal the web's `tokens.css`; uploads the
   APK.
6. **Android app UI tests (Appium, emulator)**: installs that APK on Google's Android Emulator
   (Pixel 7 profile, Android 16, x86-64 image, accelerated by KVM) and starts Appium 3 with the
   UiAutomator2 driver. Runs the app tests in both display configurations, then
   `tools/fault_check.py --app-only` (the planted defects against the app cases), and uploads the
   report with any failure screenshots and UI trees, and the Appium log.
7. **iOS app (build, unit and UI tests)**: on GitHub's standard macOS runner (`macos-26`, arm64, Xcode
   26.6 by default), boots the iPhone 17 of the newest iOS runtime by UDID (every runtime on the image
   has one), runs the app's 35 unit tests with `xcodebuild test`, which also builds the app for the UI
   tests, installs Appium 3 with the XCUITest driver, runs the iOS tests, then
   `tools/fault_check.py --ios-only`, and uploads the report, the unit tests' result bundle, any failure
   screenshots, UI trees and proxy logs, and the Appium log. The first session builds WebDriverAgent; the
   job took 15 to 23 minutes in its first three green runs. Appium runs headless there
   (`isHeadless`, set when `CI=true`), so it uses the simulator the job booted instead of restarting it
   with a window.

A separate, manually triggered `load.yml` runs the k6 load test followed by the reconciliation
(section 6).

Which tests fail under `race` depends on timing (six locally, five in CI), so `fault_check.py`
requires only the two that fail every time: CON-001 and the balance-equals-ledger invariant.

CI runs on GitHub's ARM64 runners (`ubuntu-24.04-arm`), the same architecture as the development
machine (OCI Ampere), so a local pass cannot turn into a CI failure through architecture differences.
Two kinds of job are the exception. The iOS job runs on macOS (arm64), the only system with Xcode and
the iOS simulator. The two Android jobs run on x86-64 (`ubuntu-24.04`): Google ships the build
tools for x86-64 Linux only, and the emulator needs KVM, which GitHub's x64 runners provide. The
Android app does not depend on the architecture: its only native library, from AndroidX, is built for both.

## 9. AI-assisted development

I built this project with **Claude Code**, an AI coding agent running on my OCI development server.
My background is ten years of manual testing on payment systems; this repository is part of my move
into test automation (SDET). The work was divided as follows:

| My part | Claude Code's part |
|---|---|
| Set the requirements: the scope of the wallet API, which payment risks to cover, no Docker for the API and its tests, CI required | Proposed a plan, a folder structure and a test-case list from those requirements |
| Reviewed the test-case list item by item and decided on changes (for example, supporting two decimal places in amounts) | Wrote the API, the test framework and the tests |
| Read the explanation of each step, ran it myself, and moved on only once I understood it | Ran each step, reported the results, and diagnosed failures |
| Decided when to commit and when to make the repository public | Committed in small steps, with messages that explain what changed and why |
| Chose the web scope and tools: Playwright for Python in the same suite, Figma for the design and its visual direction, no transfer screen; asked for WEB-013 and WEB-014 when the traceability table showed two uncovered rules that guard against double charges | Built the Figma design system, the front end, its specification and the UI tests; found and fixed a double-charge regression it had itself introduced (next section) |
| Set the goal of one test platform for web, Android and iOS, and started the iOS app in stages | Proposed the stages; built the first one: the SwiftUI app and its Appium (XCUITest) cases |

**How I verify that the AI-written tests work:** a fully passing suite is not accepted as evidence.
Defects are planted in the system under test, each one must make its assigned tests fail, and CI
checks this automatically on every push to main. During development this approach caught real problems
(see the next section).

## 10. Issues found during development

Each of these is recorded in the commit history.

| Issue | How it was found | Fix |
|---|---|---|
| Balance requests occasionally returned 500 | Running concurrent scenarios by hand after the payment endpoint was written | FastAPI may open and close the same SQLite connection on different threads; `check_same_thread` is now disabled |
| The "empty Idempotency-Key" test never actually sent an empty key | The test failed and was traced to the client layer | `key or new_key()` treated an empty string as missing; a key is now generated only when the argument is `None` |
| The floating-point defect did not show up | With `float_math` on, the precision tests still passed | 33.33 happens to be exact in floating point; it was replaced with values verified to fail, such as 19.99 |
| Custom pytest options were reported as unrecognized | Rehearsing the CI commands locally | Options are passed as `--opt=value` (section 7) |
| With duplicated payments, all seven database invariants still passed | k6 with `no_idempotency` on: the k6 retry checks failed, but the reconciliation passed | The books balanced; the customer had simply been charged twice. A rule was added: every payment has a matching Idempotency-Key |
| Newman sent amounts that differed from the CSV | The case "scientific notation 1e3 must be rejected" received 201 | Newman converts unquoted CSV fields to numbers: `1e3` is sent as `1000` and `10.50` as `10.5`. Amount columns are now always quoted |
| In the web page, pressing *Pay* again after "no answer" would have charged twice | Reviewing the "no answer" screen before any UI test existed: the main button created a new Idempotency-Key | The pending attempt and its key are kept; Retry and the main button both resend them |
| The same double charge came back when Pay was split into two steps: Back from Confirm, then the same amount again, sent a new key | Writing WEB-013. The specification had described this behaviour as correct, and the browser check run for the redesign had asserted it | Only a different amount ends a pending attempt (compared as money: `30` equals `30.00`). WEB-013 covers both paths; the mutation `back_forgets_the_attempt` restores the old behaviour and must make it fail. Recorded in SPEC.md §11 |
| A double-tap test with Playwright's `dblclick` still passed with the in-flight guard removed | The mutation check: the mutant survived | React disables the button between the two clicks, so the guard was never reached. WEB-007 dispatches both clicks in one JavaScript task, the gap the guard exists for |
| One test hook read `100.00` on the top-up receipt and `63.00 TWD` on the payment receipt | Listing the hooks for SPEC.md | Every amount hook now holds the number only |
| On a small phone, the Start screen's error message appeared below the visible area: the user tapped and saw nothing happen | The Android app's first Appium run on a 360 × 640 dp screen could not find the message (UiAutomator sees only what is on screen). The web had the same problem at a 360 × 640 viewport; its Playwright tests had passed, because a text assertion does not require the element to be in view | Both clients show the message under the button that caused it and scroll it into view (SPEC L-04). WEB-011 now checks it on a 360 × 640 viewport and fails without the fix |
| Two more messages out of view, in the Android app only: after a refund, the reloaded refund list pushed the success message down; after a refund got no answer, Retry sat below its warning | The same Appium checks on the 360 × 640 dp screen. The web keeps the first in view through the browser's scroll anchoring, which Compose does not have | The app reloads before it shows the message, and brings the whole refund form into view when its state changes |
| The app could charge twice after Android killed it on the payment receipt: it reopened on Confirm with **Confirm payment** enabled, and tapping it was a second payment with a new key | A full QA pass before the app's Appium tests: the app was sent to the background on the receipt and its process killed (`am kill`), as Android does under memory pressure. The server then held two payments | The receipt is saved with the screen's state and shown again when the app is reopened (SPEC.md N-01, APP-017) |
| The API accepted `１００` (full-width digits) and charged 100.00 | A probe that sends the same 40 inputs through both clients and compares the results: the web showed `１００` on Confirm, the app `100.00` | Python's `\d` matches any script's digits, and so does Android's (ICU), while the app's unit tests run on a JVM where it does not. The API and both clients use `[0-9]`; four CSV cases and a unit test that compiles the app's pattern in Unicode mode |
| Confirm showed ` 5 ` as `5.00` with a balance after, and the API then refused it | The same probe | Both clients trimmed spaces before deciding whether an amount was plain; the API does not. They now use the API's grammar exactly (WEB-005) |
| Long values broke the layout: a balance of `999,999,999,999.99` was clipped on the web; in the app, a 50-character name overlapped the *From* label and *TWD* stood in a column | Screenshots with the longest values the API allows. The web's layout check looked only for horizontal scrolling, and a card clips without making the page wider | Both clients step the balance's text style down by length and move the currency to the next line when needed; the app keeps a label at least as wide as its longest word, as a browser does. WEB-011 now checks for content clipped by a card, with the longest values |
| The app's layout check passed with the two layout defects of the QA pass put back | Running each fix's removal against APP-011 (one change to the app at a time) | Android drops a text squeezed to zero width from the accessibility tree, so the crushed label was drawn but absent from every element list. Rows made of several texts now carry hooks, and the check requires every part of every row; both removals now fail APP-011 |
| Reading a History longer than the screen stopped three rows early | APP-010 with twelve entries | `mobile: scrollGesture` reported "cannot scroll further" while it still could. The tests compare the screen before and after each scroll instead |
| The API document at `/docs` described responses the API never gives: a `422 Validation Error` shaped `{"detail": [...]}` on every route, successes as any content, and Idempotency-Key as optional | Preparing a demo in Swagger UI: a validation error is really a 400 `INVALID_REQUEST`. The JSON Schema tests checked the responses, never the document | Each route declares its real responses (`app/responses.py`, documentation only: responses are sent as before); FastAPI's default 422 is removed and the key is marked required. CTR-004 requires the document to list exactly the statuses the API answers with, each in the documented format; it fails on the previous version |
| Keyboard focus could land entirely behind a sticky bar: on a 360 × 640 screen, Tab to *Use another wallet* on Home left it behind the tab bar and Shift+Tab left the balance toggle behind the top bar (Chromium, WebKit); in Firefox, a History row ended behind the tab bar | Checking axe's report that the same link was too small (`target-size`, WebKit only). That report depended on the scroll position at the time of the scan; the focus problem was real | The page sets scroll padding for its sticky top bar and tab bar, and WEB-016 tabs through every screen. axe's `target-size` is left to WEB-011, which requires 44 × 44 px |
| A 20-digit amount crashed the Android app on Confirm; the web showed a different number from 2^53 up (`9007199254740993` as `…992.00`) | Comparing the three clients' code and screens side by side: the iOS app, written last, guarded its cents against overflow, and the other two did not. Reproduced on the emulator: `NumberFormatException` in `Money.toCents` | The API takes at most 12 digits before the point, and the clients' *plain* grammar had no such limit. All three now use the API's grammar exactly, so an amount they convert always fits, and a longer one is shown as typed (SPEC R-04). WEB-005, APP-005 and IOS-005 send 13 and 20 digits |
| Every row of text on iOS was shorter than on the web and Android: a ledger row 61 pt instead of 67, a receipt row 43 instead of 47 | The same comparison: positions on iOS drifted upward screen by screen | SwiftUI has no line height. The app set the difference from Inter's own as line spacing, which goes only between lines, so one line of Body was 18 pt high instead of 22. Half of it now also goes above and below the text, as CSS and Compose do. IOS-018 measures the distance between rows and failed before the fix |
| Seven small layout differences between the clients, such as *Use another wallet* pinned to the bottom of Home on the web only, the web's hide-balance icon darker than the apps', and the apps' summary cards up to 28 dp taller than the web's | The same measurement, extended to every screen the web and Android share | Figma has no screen frames, so each was decided by the intent written in the code, then consistency within a client, then the majority, and written down as SPEC §7.7. The iOS receipt values became Body/Strong in tabular figures (IOS-019). SPEC §11, 2.13 lists all seven |
| On the web, amounts were not in tabular figures: the digits in History did not line up, and the receipt's `120.00` was 7 px narrower than in the apps | The same comparison, measuring every hook at the same width. The CSS said `tabular-nums`, and the development server showed it | Vite's CSS minifier moved `font-variant-numeric` before the `font` shorthand in the same rule, and the shorthand reset it; a list row's text style also reset what the row passed down. The text styles are now longhands. WEB-017 measures the drawn digits and failed in all three engines before the fix |
| With the amount field's label detached, leaving only the placeholder `0.00`, the axe scan still passed | The mutation check for WEB-015: the mutant survived in all three engines | axe counts a placeholder as a field's name; a placeholder disappears as soon as the user types. WEB-015 now also requires every input to be tied to a visible `<label>` |
| A test could start on the previous test's screen | Choosing how the iOS app keeps K-08's state: a throwaway app on the simulator, ended in eight ways | iOS restores the screen state it saved when the app last went to the background even after the app is ended in the foreground, which is how each test closes the app before the next. The tests' fixture now deletes that state before every launch, as Android's `force-stop` does; without it, the case after IOS-017 did not start on Start |
| On Payment detail, everything under the summary card sat up to 4 px lower on the web than in the apps | Measuring History, Top up and Payment detail on the three clients at 402 wide, every text's centre from the top bar (2.16) | The web's card border took 1 px above and below; the apps draw the hairline inside the card. The web now draws it as an inset box shadow, which looks the same and takes no room. WEB-018 failed in all three engines before the change |
| In iOS messages and on the receipt heading, the text started 5 pt left of where the web and Android put it | The same measurement, then side-by-side crops of the screenshots | The SF Symbols had no frame, so they were only as wide as the symbol, about 19 pt; the other clients' icons are 24. They now take a 24 pt box. IOS-020 measured 67 and 47 pt before the change, 72 and 52 after |
| Every line of text on iOS was 1/3 pt taller than its token, so the sixth History row sat 3 pt lower than on the other clients | The same measurement: each row was within IOS-018's 1 pt, but the rows added up | A probe build reported SwiftUI's own heights: a Text is one pixel taller than the font's line height, on 2x and 3x screens alike (1/3 pt on an iPhone 17, 1/2 on an iPhone SE). That pixel now comes off the padding, and rows are exactly 66 pt plus the hairline on both. IOS-018 now also checks six rows together: 338 pt before the change, 335 after |
| In CI only, after a test killed the app and opened it again, the app could not reach the test proxy: Retry sent nothing, and Home said *No answer from the server.* | The new iOS CI job failed twice, in IOS-015 both times and in IOS-017 once, while IOS-015 passed 25 times in a row on the Mac. The screenshot could not tell a lost tap from a request without an answer, so failing tests now also keep the proxy's requests: in the second failure, no request had reached it after the relaunch | Appium's `mobile: launchApp` does not relaunch an app that is already running: it brings it to the front, and the launch arguments do not apply (measured on the Mac: same process, the old `-apiBaseUrl`). The tests now launch with `simctl launch --terminate-running-process` and read the app's own command line after every launch. Whether a process was already there before those two relaunches was not seen: in the twelve relaunches of the next three CI runs, all green, there was none |
| The first CI run on `main` after the iOS job was merged failed before any iOS test began: "Device … did not finish booting within 120000ms" | Appium's log for that run, then for the three green runs before it | The XCUITest driver restarts a simulator that is booted without a window, to show one. It had done so in every run: 123, 28 and 70 seconds in the green ones, more than its 120-second limit in the red one. In CI the tests now ask for a headless session, which uses the simulator as booted. Only in CI: headless, the driver also quits the Simulator app, which on a developer's Mac may be in use |
