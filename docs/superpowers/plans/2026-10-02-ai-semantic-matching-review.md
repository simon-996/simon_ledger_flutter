# AI Semantic Matching and Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use AI semantics to choose existing categories, safely match ledger people, and show truthful payment/split previews.

**Architecture:** API loads authoritative ledger people and receives expense/income category lists from Flutter. AI generates suggestions; server validates membership and resolves deterministic person candidates. Flutter maps remote identities, persists explicit payment and match metadata, and presents editable confirmation without inventing completed states.

**Tech Stack:** Java 21/Spring Boot/JUnit; Flutter/Riverpod/SharedPreferences/flutter_test.

## Contract

Parse request adds optional `expenseCategories` and `incomeCategories` string arrays; omitted arrays use product defaults, explicit empty arrays remain empty. Trim/deduplicate; maximum 128 categories per list, 64 Unicode characters per name. No keyword-to-category table.

Entry retains existing fields and adds:

```json
{
  "paymentMode": "unconfirmed",
  "personMatches": [
    {
      "sourceName": "陈欣",
      "role": "participant",
      "personUuid": "remote-person-uuid",
      "matchedName": "陈鑫",
      "approximate": true,
      "candidatePersonUuids": ["remote-person-uuid"]
    }
  ]
}
```

`paymentMode` accepts `unconfirmed`, `shared_wallet`, `person`. For income it does not control confirmation. A resolved payer implies `person`; missing payer does not imply a shared wallet. `role` is `participant` or `payer`. Metadata is optional for legacy clients/drafts; unresolved old names remain usable.

## Task 1: API context, semantic classification, and person matching

**Files (API repository):**
- Modify `src/main/java/com/simon/ledger/dto/req/AiParseReq.java`, `dto/resp/AiDraftResp.java`.
- Modify `service/impl/AiBookkeepingService.java`, `service/impl/AiDraftValidator.java`, `infrastructure/ai/DeepSeekDraftClient.java`.
- Create focused category-context and person-matching helpers under `service/impl/`; add a phonetic dependency only after verifying its official documentation.
- Tests: existing `AiDraftValidatorTests`, `AiBookkeepingServiceTests`, `DeepSeekDraftClientTests` plus focused helper tests.

- [ ] Write failing tests using arbitrary custom categories (not just breakfast/transport examples), invalid category output, expense/income separation, context propagation, remote person identities, unique homophones, duplicate/multiple candidates, missing self association, and explicit wallet/unknown payment modes.
- [ ] Run `JAVA_HOME="$(/usr/libexec/java_home -v 21)" mvn -Dtest=AiDraftValidatorTests,AiBookkeepingServiceTests,DeepSeekDraftClientTests test`; confirm failures reflect absent behavior.
- [ ] Send serialized names/categories as untrusted data to AI, preserve original mentioned names, ask for semantic selection exclusively within the supplied category list. Do not implement description keyword mapping.
- [ ] Resolve exact unique matches, then unique full-name phonetics without tones. Preserve ambiguity; weak one-character edits/abbreviations are candidates requiring confirmation. Only current ledger active people are eligible; “我” uses linked user ID.
- [ ] Validate output category against the list for entry type; unsupported suggestions become null without losing the rest of the draft. Maintain original names and role-specific candidate metadata.
- [ ] Validate input category bounds before provider invocation; do not log private descriptions or provider keys. Keep the existing provider parse overload for compatibility where necessary.
- [ ] Run focused API tests and the complete non-live suite; inspect diff for unrelated changes. Do not push/deploy during this task.

## Task 2: Flutter contract, identity normalization, and persistence

**Files:** `lib/core/models/ai_draft.dart`, new `lib/core/services/ai_draft_identity_mapper.dart`, `lib/core/repositories/ai_bookkeeping_repository.dart`, `lib/features/transactions/presentation/widgets/ai_bookkeeping_flow.dart`; tests under `test/ai_draft_identity_mapper_test.dart`, `ai_bookkeeping_repository_test.dart`, `ai_bookkeeping_flow_test.dart`, `ai_draft_queue_test.dart`.

- [ ] Write tests that request custom expense/income arrays, serialize new match/payment fields, and normalize remote UUIDs to local UUIDs while leaving truly missing UUIDs unresolved.
- [ ] Run `/Users/simon/enviroment/flutter/bin/flutter test --no-pub test/ai_bookkeeping_repository_test.dart test/ai_draft_identity_mapper_test.dart`; observe red before implementation.
- [ ] Add optional request named parameters `List<String>? expenseCategories, List<String>? incomeCategories`; flow reads `TransactionCategoryPreference.read()` at parse time and passes full lists.
- [ ] Add typed `AiPersonMatch` and `AiPaymentMode` support with backward-compatible JSON. Missing payment mode is unresolved unless an existing valid payer identifies personal payment.
- [ ] Map participant/payer/candidate UUIDs through active current-ledger `Person.uuid` / `Person.syncedRemoteUuid` aliases, deterministically and idempotently. Map returned drafts before queuing and restored drafts before review; persist restored mapping without changing operation identity or position.
- [ ] Update disclosure to mention ledger person names/category names and bump its consent version. Do not send unrelated people or account identifiers from Flutter.
- [ ] Run model/repository/queue/flow tests and update fake repository signatures to mirror the production interface.

## Task 3: Explicit confirmation and compact amount preview

**Files:** `lib/features/transactions/presentation/widgets/ai_draft_review.dart`; create a focused person-resolution widget if needed. Extend `transaction_split_summary.dart` with an opt-in compact AI presentation so existing manual forms keep their current contract. Tests: `ai_bookkeeping_flow_test.dart`, `transaction_split_summary_test.dart`.

- [ ] Write regression tests for zero selected people, unknown payment, remote ID matches, role-specific ambiguous names, narrow/wide layout and larger text.
- [ ] Run focused tests and inspect expected failures before changing widgets.
- [ ] Replace internal stale-ID placeholder labels with standalone readable status text and short action labels. Show actual original names, suggested match names and role; user can override/ignore suggestions.
- [ ] Use a single nullable payment-mode selector; no selected wallet before confirmation. Choosing personal payment still requires a payer. Persist the explicit state on every draft edit; confirm rejects unresolved payment, people, category or date.
- [ ] Keep original amount primary and converted amount secondary with “按账本汇率约合”. Hide unfinished split numbers; show “请选择承担人” and “付款方式待确认” separately. Preserve existing conversion precision and manual summary behavior.
- [ ] Run focused widget tests and full Flutter tests. Correct fixture expectations only where old fixtures implicitly assumed a wallet; add explicit legacy-state tests rather than weakening validation.

## Task 4: Integration verification and review

- [ ] Verify the approved spec against changed source, request/response names, legacy draft recovery, consent scope and security boundaries.
- [ ] Run `/Users/simon/enviroment/flutter/bin/flutter test --no-pub --reporter expanded` and `flutter analyze --no-pub` for changed paths; use Java 21 for `mvn test`.
- [ ] Review spec compliance first, then code quality with separate read-only reviewers; fix actionable findings and rerun relevant checks.
- [ ] Build Web and API locally; do not claim real provider semantics from fake-provider test results.
- [ ] Report local implementation/verification status. User requested modification, not a new release in this turn; push/deployment remain a separate authorization unless they ask while work is ongoing.
