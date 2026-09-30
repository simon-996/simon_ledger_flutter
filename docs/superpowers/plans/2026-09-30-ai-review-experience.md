# AI Review Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make AI bookkeeping drafts safe and easy to review on a phone.

**Architecture:** Keep the existing `AiBookkeepingFlow` as queue controller and `AiDraftReview` as the form. Persist edits through `AiDraftQueue` using stable item IDs. Reuse the manual bookkeeping category selector and preferences, and keep the existing transaction save callback.

**Tech Stack:** Flutter, Dart, Material widgets, SharedPreferences, flutter_test.

---

## File map

- `lib/core/services/ai_draft_queue.dart`: persist edited drafts, original batch positions, and migration fallback.
- `lib/core/services/ai_audio_recorder.dart`: notify the flow when automatic recording stop fails.
- `lib/features/transactions/presentation/widgets/ai_draft_review.dart`: grouped form, explicit uncertainty resolution, category/date/person options.
- `lib/features/transactions/presentation/widgets/ai_bookkeeping_flow.dart`: fixed progress/header/footer, close/skip behavior, recording states, error messages.
- `lib/features/transactions/presentation/widgets/bookkeeping_tab.dart`: pass actual device zone and validate selected category on save.
- `test/ai_draft_queue_test.dart` and `test/ai_bookkeeping_flow_test.dart`: behavioral regression coverage.

### Task 1: Persist edited drafts and progress

**Files:** `lib/core/services/ai_draft_queue.dart`, `test/ai_draft_queue_test.dart`

- [x] Add a failing queue test: add two drafts, update the second amount, remove the first, reopen the queue, and expect the second draft to retain the edited amount and position `2/2`.
- [x] Run `flutter test test/ai_draft_queue_test.dart` and observe the missing update/progress behavior fail.
- [x] Add `position` and `total` to `AiDraftItem` with backward-compatible JSON defaults; add `AiDraftQueue.update(ledgerUuid, uuid, draft)` and preserve the item IDs and position.
- [x] Run `flutter test test/ai_draft_queue_test.dart` and expect all tests to pass.

### Task 2: Review fields and validation

**Files:** `lib/features/transactions/presentation/widgets/ai_draft_review.dart`, `test/ai_bookkeeping_flow_test.dart`

- [x] Add failing widget tests: existing category renders as a selectable option; unknown suggestion cannot be saved as category; unresolved person cannot be confirmed until selected or ignored; changed amount survives rebuilding from queue.
- [x] Run `flutter test test/ai_bookkeeping_flow_test.dart` and confirm each new assertion fails for the expected missing behavior.
- [x] Replace the category text field with `CategorySelector` and the existing category creation sheet. Resolve unknown suggestions explicitly. Add a date/time picker and make the empty-time fallback visible. Group fields with section headings and a concise review summary.
- [x] Emit an updated `AiDraft` on each edit and await pending writes before confirmation or dismissal. Validate the selected category against the current type's category list and require explicit resolution of each unknown person.
- [x] Run the widget tests and expect all tests to pass.

### Task 3: Queue shell, voice state, and errors

**Files:** `lib/features/transactions/presentation/widgets/ai_bookkeeping_flow.dart`, `lib/features/transactions/presentation/widgets/bookkeeping_tab.dart`, `test/ai_bookkeeping_flow_test.dart`

- [x] Add failing widget tests for stable `2/2` progress after reopening, skip confirmation, exit summary, recording time, preventing parse during transcription, and preserving preexisting text before transcript replacement.
- [x] Run `flutter test test/ai_bookkeeping_flow_test.dart` and confirm failures come from the missing interactions.
- [x] Build a fixed header and footer around the scrollable review content. Show source text and progress, confirm skip, summarize on exit, and preserve current edited draft.
- [x] Make recording, transcription and parsing mutually exclusive. Show recording duration; ask before replacing nonempty text. Use `FriendlyError` to distinguish API failures while preserving input.
- [x] Pass the device's current UTC offset, rather than a hard-coded zone, in parse requests. Keep the existing save callback and idempotency behavior.
- [x] Run widget tests and expect all tests to pass.

### Task 4: Verify

**Files:** the files above only.

- [x] Run `dart format` on changed Dart files.
- [x] Run `flutter test test/ai_draft_queue_test.dart test/ai_bookkeeping_flow_test.dart test/ai_audio_recorder_test.dart test/bookkeeping_tab_test.dart`.
- [x] Run `flutter analyze` and inspect every diagnostic.
- [x] Review the diff against the approved design, check that unrelated worktree changes were untouched, then report remaining limitations.

