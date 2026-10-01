# Live Bidirectional Ledger Rate

**Goal:** Show the entered exchange rate immediately and allow either foreign-to-CNY or CNY-to-foreign entry.
**Architecture:** Keep the existing saved exchangeRateToCNY contract. A direction switch reciprocates valid full-precision input; both equations update while typing. Normalize reverse input on save. CNY stays fixed at 1; invalid/empty/non-finite reciprocal values cannot save or show a stale preview. Editing uses the same component.
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
