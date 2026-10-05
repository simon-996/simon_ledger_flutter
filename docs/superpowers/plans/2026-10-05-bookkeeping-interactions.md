# Bookkeeping Interactions Implementation Plan

> **For agentic workers:** Use executing-plans inline in the existing feature worktree. Track steps below and run verification before committing.

**Goal:** Make transaction feedback, currency selection and date/time editing consistent on mobile and desktop.

**Architecture:** Reuse AppNotice and CurrencyLabel; extract the shared transaction date control into a focused widget. Return date/time precision separately from the DateTime value so AI date-only semantics survive editing.

**Tech Stack:** Flutter Material/Cupertino, existing theme, flutter_test; no new packages.

## Task 1: Feedback

Files: `lib/core/widgets/app_components.dart`, `lib/features/transactions/presentation/widgets/bookkeeping_tab.dart`, `test/bookkeeping_interactions_test.dart`.

- [x] Write failing tests asserting `find.byType(SnackBar)` is empty after saving, the notice lies above the save button, and two saves followed by undo preserve the first record.
- [x] Run `flutter test test/bookkeeping_interactions_test.dart --reporter expanded` and confirm these assertions fail.
- [x] Replace the transaction SnackBar with `AppNotice.show(context, message, type: AppNoticeType.success, actionLabel: '撤销', onAction: undo, duration: const Duration(seconds: 6))`; keep UUID and account guards in undo. Use top-right alignment on screens at least 720 px wide, live-region semantics, reduced-motion behavior, and no automatic dismissal for accessible-navigation actionable notices.
- [x] Run the feedback tests and existing `test/bookkeeping_tab_test.dart`.

## Task 2: Currency

Files: `lib/core/widgets/currency_widgets.dart`, `lib/features/transactions/presentation/widgets/transaction_form_components.dart`, currency consumers' widget tests.

- [x] Add failing tests for `¥ CNY · 人民币`, direct CNY/USD selection at 160 px, and searching a currency by symbol.
- [x] Run the focused test file and confirm failure.
- [x] Add shared symbol/label formatting; make two choices direct regardless of available width, retaining readable code and symbol on compact tiles; use complete semantic labels. Include symbols in search. Constrain the selection sheet against keyboard height and use a compact dialog on wide screens.
- [x] Run `flutter test test/transaction_form_components_test.dart test/transaction_capture_test.dart test/create_ledger_sheet_test.dart` and update the old label expectations.

## Task 3: Date/time

Files: create `lib/features/transactions/presentation/widgets/transaction_date_control.dart`; re-export from `transaction_form_components.dart`; update `ai_draft_review.dart`; add `test/transaction_date_control_test.dart`; update obsolete dual-picker tests in `transaction_ux_test.dart`.

- [x] Add failing behavioral tests: yesterday selection commits only after completion; cancellation leaves callback untouched; unedited null date stays null; invalid hour blocks completion; date-only AI edits remain DAY; specifying HH:mm returns TIME; short keyboard layouts and desktop picker do not overflow.
- [x] Run these tests and confirm the missing behavior.
- [x] Implement a single draft-state picker with quick date chips, optional CalendarDatePicker, time fields/Cupertino picker and one completion button. Keep existing helpers that preserve date/time precision. Expose `hasTime` and `onTimePrecisionChanged` on the control; AI passes its current precision and updates it from the committed result. Preserve save-time now when new records are untouched.
- [x] Run date, transaction UX, edit and AI regression tests.

## Task 4: Verification and review

- [x] Run `dart format lib/core/widgets/app_components.dart lib/core/widgets/currency_widgets.dart lib/features/transactions/presentation/widgets test`.
- [x] Run `flutter test --reporter expanded`, `flutter analyze`, `flutter build web --no-wasm-dry-run` and inspect exit codes.
- [x] Inspect mobile and desktop screenshots of the new shared picker, including small-screen keyboard and large-text layout; correct actual overflow if found.
- [x] Review the diff for account-safe undo, precision transitions, canceled picker state and obsolete label/dual-picker references; record evidence in the design document and commit the verified change locally.
