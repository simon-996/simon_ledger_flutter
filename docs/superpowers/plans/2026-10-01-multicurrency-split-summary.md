# Multi-currency Split Summary Implementation Plan

**Goal:** Show a total and per-person amount for every currency supported by the current ledger, updating with amount, currency and participants.

**Architecture:** The shared TransactionSplitSummary receives its ledger and renders the entered currency plus known converted currencies. Current ledgers support CNY and one configured foreign currency. Normalize codes, validate positive finite amounts and rates, and avoid guessing unknown conversions. Round for display only. A responsive currency row pairs total and per-person values; income uses per-person receipts. Apply the component to manual entry, edit and AI review.

**Tech Stack:** Flutter, existing Ledger exchangeRateToCNY and supportedCurrenciesForLedger, widget tests.

- [x] Add an integration regression to transaction_ux_test: USD ledger at 7.2, amount 100 and 2 participants must display USD total 100 / each 50 and CNY total 720 / each 360; it must fail before implementation.
- [x] Add ledger context to shared summary and all three call sites. Use amount * rate for foreign -> CNY and amount / rate for CNY -> foreign; only render finite results. Show placeholders for no amount or participants and a rate hint for invalid conversion rates.
- [x] Test reverse currency entry, income, zero participants, invalid numbers/rates and narrow / large-text layouts. Update existing summary assertions for the grouped design.
- [x] Verify affected form suites and analyze, independently review, merge master, restart and inspect a populated screenshot without modifying user data.

Authorized by the user's request to add other currency totals and individual amounts to bookkeeping.

## Verification

- Regression failed against the original summary before implementation.
- Full Flutter suite: 347 tests passed.
- Flutter analyze: no issues.
- Independent reviewer found no issues in conversion, persistence compatibility, reactive updates or layout.
- Populated real-font 390px capture inspected: D:/workplace/projects/simon-ledger/.tmp/ux-multi-currency/bookkeeping-multi-currency-390.png. Fixture USD 100 / 2 participants / rate 7.2 shows USD total 100 / each 50 and CNY total 720 / each 360. No user ledger was created for capture.
- Web release build passed (42.2s).

## Delivery

- Implementation 18b4a81 fast-forward merged into master.
- Restarted master Flutter web-server at http://127.0.0.1:5317/ and reloaded the existing browser tab; application loaded normally.
- Frontend and http://127.0.0.1:18080/api/health both returned HTTP 200.
- Populated summary was verified using isolated widget-test fixtures and the real-font capture above; browser data was not modified.
