# Local Self Cloud Identity Implementation Plan

> Execute inline in the current session, with test-driven-development and an independent code review before completion.

**Goal:** Convert explicit local self into the claiming cloud account without changing other people or losing transaction references.

**Architecture:** Persist self provenance on Person. DatabaseService clones and remaps shared participants when claiming a ledger. Existing repositories keep per-person remote mappings and repair verified legacy self records using the existing person update API. Profile projection matches account identity only.

**Tech Stack:** Dart, Flutter, SharedPreferences, existing ledger/person APIs.

## Task 1: Reproduction tests

- [x] Add `test/local_self_identity_test.dart` using real database/repositories and an API boundary double. Assert one displayed owner, unchanged same-name manual participant, independent mappings after two claims, and preserved historical payer/participant references.
- [x] Extend `test/profile_projection_service_test.dart` to assert that localAccountUuid alone does not identify self and guest nickname matches are not rewritten.
- [x] Extend creation tests to assert the persisted self flag and prevent same-name manual selection.
- [x] Run `flutter test --no-pub test/local_self_identity_test.dart test/profile_projection_service_test.dart test/create_ledger_sheet_test.dart` and verify expected failures before implementation.

## Task 2: Stable self provenance and profile projection

- [x] Add Person.isLocalSelf and a stable legacy UUID compatibility getter; serialize the flag in DatabaseService.
- [x] Mark system-created self in database initialization, profile fallback, ledger creation, and explicit self joining. Preserve metadata through person editing and copying.
- [x] Replace nickname/avatar/ownership self heuristics with explicit provenance for guest people and linkedUserUuid for account people.
- [x] Run the focused tests and verify profile/creation scenarios pass.

## Task 3: Ledger claim and historical references

- [x] In DatabaseService.claimLedger, collect ledger and historical transaction references, compute shared guest references, copy referenced people and only bind self to the current account/profile.
- [x] Use `claimed:<ledgerUuid>:<personUuid>` for a shared or colliding person; remap only that ledger's personUuids and its historical personUuids/payerPersonUuid.
- [x] Keep the untouched guest records and other account mappings. Verify sequential claims and failed upload retry retain stable references.

## Task 4: Existing uploaded self and verification

- [x] Before syncing pending people, verify unlinked local self's mapped remote record against that ledger's people endpoint, then queue an ordinary versioned person update or adopt the already-linked remote record.
- [x] Verify existing-data repair, identity preservation, request payloads, and single owner chip.
- [x] Run all affected tests, `flutter analyze --no-pub`, and `git diff --check`; request an independent review and address concrete findings.

## Verification results

- Full Flutter suite: 251 tests passed.
- Flutter analyze: no issues found.
- Independent review: legacy alias/history omission fixed; follow-up review found no further actionable issues.
- git diff --check: passed.
