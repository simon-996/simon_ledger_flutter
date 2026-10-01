# Live Bidirectional Ledger Rate

**Goal:** Show the entered exchange rate immediately and allow either foreign-to-CNY or CNY-to-foreign entry.
**Architecture:** Keep the existing saved exchangeRateToCNY contract. A direction switch reciprocates valid full-precision input; the inverse equation updates while typing; the entered direction is shown in the input. Normalize reverse input on save. CNY stays fixed at 1; invalid/empty/non-finite reciprocal values cannot save or show a stale preview. Editing uses the same component.
**Tech Stack:** Flutter / Riverpod / existing widget tests.

- [x] Reproduce static '?' helper, then verify live valid/invalid previews.
- [x] Add entry direction, invert on switch without rounding input and normalize on save.
- [x] Verify saved results, editing and CNY/currency changes, plus narrow/large-text layouts.
- [x] Full tests, analyze, build, independent review, merge master and restart preview.

User explicitly authorized realtime preview and either rate-entry direction.

## Verification

- Live preview regression failed against the original static helper, then passed after implementation.
- 11 create/edit ledger widget tests pass, including inverse save, invalid values, CNY reset and 280px / 1.5x text.
- Full suite: 338 tests passed.
- Flutter analyze: no issues.
- Independent reviewer found no issues; canonical persistence and reciprocal precision remain compatible.
- Web release build passed (75.5s).

## Delivery

- Fast-forward merged implementation commit 172436e into master.
- Restarted Flutter web-server from master at http://127.0.0.1:5317/; HTTP 200.
- Existing API health at http://127.0.0.1:18080/api/health returned HTTP 200.
- Browser verified live 7.2 forward entry, automatic inverse on direction switch, and 0.125 reverse entry yielding canonical rate 8. No ledger was created during browser verification.
- Screenshot: D:/workplace/projects/simon-ledger/.tmp/ux-rates/rate-inverse-master.jpg.

## Follow-up: direction and preview layout

User reported clipped entry direction labels and misaligned rate equations. Chip labels inherit a single-line fade constraint; trying multiline chip labels exposed a narrow / large-text chip layout assertion. Use naturally sized outlined selection buttons with wrapping text, minimum 48px target and explicit selected semantics. Both equations now share one helper column, style and inset. Colors come from the global theme.

- Regression checks first failed with a 20px difference between equation left edges.
- 13 create/edit ledger tests now pass, including label bounds / clipping / aligned equations at 489px normal text and 280px / 1.5x text, plus existing numeric and inverse-save checks.
- Flutter analyze: no issues. Independent review found no blocking issues in selection semantics, keyboard activation or helper/error layout.
- Merged fix fa2a9e5 into master and restarted web-server successfully; frontend and API both returned HTTP 200.
- Actual 489px browser preview verified complete direction labels, both selected states, and equal left alignment of the two equations. Screenshot: D:/workplace/projects/simon-ledger/.tmp/ux-rates/rate-layout-fixed-master.jpg. No ledger was created.

## Follow-up: inverse preview only

The input already displays the entered A-to-B equation. The helper now displays only B-to-A and follows direction changes; empty/invalid input still shows the existing hint. Updated create/edit ledger assertions pass: 13 widget tests, including narrow / large-text controls and normalized inverse saves.
