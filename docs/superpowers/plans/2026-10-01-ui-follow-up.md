# UI Follow-up Implementation Plan

**Goal:** Continue the approved UI/UX polish by verifying large text and correcting inconsistent built-in control language.

**Architecture:** Keep the existing Flutter design and navigation; configure the Material app once with the SDK localization delegates. No per-picker language overrides. The app's Chinese interface uses zh_CN consistently.

**Tech Stack:** Flutter, flutter_localizations from the installed SDK, Riverpod.

- [x] Verify populated manual/edit forms at 1.5 text scale, including readable inline validation.
- [x] Reproduce English built-in date controls in a real SimonLedgerApp widget test.
- [x] Add SDK localization dependency and app-level zh_CN locale/delegates.
- [x] Verify single-day picker actions and dismissal, and range picker start/end/close labels in Chinese.
- [x] Run relevant tests, static analysis, full suite and Web build; merge master and restart preview.

This is follow-up correction within the previously approved Chinese UI and shared date-control design.

## Verification

- Regression reproduced before the fix: the real app did not show the Chinese cancel action.
- New app localization regression test passes after app-level configuration.
- 390px / 1.5 text scale manual and edit form screenshots inspected; error text is not truncated and no layout exception occurs.
- Full test suite: 333 passed.
- Static analysis: no issues found.
- Independent code review: no blocking findings; dependency changes match the installed Flutter SDK.
- Web release build with local resources and API port 18080: succeeded.

## Local delivery

- Change commit b31b547 fast-forward merged into master.
- Master dependencies resolved successfully.
- Preview restarted from master at http://127.0.0.1:5317/ and visually checked in the existing browser tab.
- Preview and API health endpoint http://127.0.0.1:18080/api/health both returned HTTP 200.
