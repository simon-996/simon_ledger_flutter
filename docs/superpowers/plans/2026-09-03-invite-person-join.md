# Invitation Join and Linked Person Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Complete the approved invitation-join slice: joining atomically creates/restores membership and a linked participant, and Flutter can use that participant immediately even if the follow-up refresh is offline.

**Architecture:** Keep the API's ledger-first mutation lock and existing optimistic versions. Return an additive join response containing `invite`, `ledger`, `member`, and `person`; retain the old invitation fields for installed clients. Flutter parses the response before writing, merges through existing UUID mapping, and invalidates participant consumers after join. Do not change the generic idempotency service.

**Tech Stack:** Spring Boot 3.5 / Java 21 / MyBatis-Plus / JUnit 5; Flutter / Riverpod / SharedPreferences / flutter_test.

---

## Scope and decisions

This is part of stage 4 of the approved `2026-08-21-full-chain-collaboration-conflict-design.md`, not completion of all stages. Invitation role selection, member management UI, and authoritative cloud statistics remain separate follow-up slices.

- Join binds on `ledger_id + linked_user_id`, never nickname. Active person wins over historical deleted candidates; use deterministic ID ordering and preserve the selected UUID.
- New member uses the invitation role. Active member retries preserve their current role and do not consume another use. Restoring an inactive member is a new admission and consumes one use.
- Unknown/deleted ledgers and disabled/expired/invalid-role invitations still fail. Quota is checked only when admitting/restoring a member, so a retry after consuming the last available use succeeds.
- Person creation, restoration, profile synchronization, membership, usage increment, and change log happen in one transaction. Versions increase only on actual changes; rollback on a failed write.
- Lock ordering is ledger, invitation/member, current account, linked person. Account reads use a current locking read so joining cannot project stale account data during profile updates. No changes to global profile locking.
- Join response preserves legacy top-level InviteResp fields while adding nested objects. Flutter accepts a legacy flat response but cannot promise a participant until the API has been upgraded.
- Flutter uses a fresh UUID-based idempotency key for each explicit join attempt. This prevents a later rejoin from replaying the original admission response; repeated requests remain safe through service-level membership/person reuse.
- Cached local UUIDs, existing participant associations, transaction references, unrelated ledgers/people, pending business edits, and unresolved conflict snapshots must not be discarded.
- Tag new ledger cache with the account UUID. If the account/session changes before the response is applied, reject it without mutating cache.

## Task 1: API atomic admission and participant reuse

**Files (API repository):**
- Create `src/main/java/com/simon/ledger/dto/resp/InviteJoinResp.java`
- Modify `src/main/java/com/simon/ledger/service/InviteService.java`
- Modify `src/main/java/com/simon/ledger/service/impl/InviteServiceImpl.java`
- Modify `src/main/java/com/simon/ledger/controller/InviteController.java`
- Modify `src/test/java/com/simon/ledger/service/impl/InviteServiceAuthorityAndVersionTests.java`
- Create `src/test/java/com/simon/ledger/service/impl/InviteJoinPersonTests.java`
- Create `src/test/java/com/simon/ledger/controller/InviteJoinContractTests.java`

- [ ] Add failing tests using real service code with mapper doubles: first join creates linked person; same-name unlinked person is untouched; active/deleted linked person is reused; changed profile increments version; unchanged retry does not; repeated active join preserves role and quota; full invite rejects a new admission but accepts active retry; invalid/expired/disabled invites and missing/disabled accounts do not mutate; member/person failed writes abort before quota completion. Preserve existing authority/version/lock-order coverage.
- [ ] Run `mvn -Dtest=InviteServiceAuthorityAndVersionTests,InviteJoinPersonTests,InviteJoinContractTests test` and confirm the missing join envelope/person behavior fails.
- [ ] Introduce the compatible DTO and change service/controller response type, including the idempotency deserialization class:

```java
@Data
@EqualsAndHashCode(callSuper = true)
public class InviteJoinResp extends InviteResp {
    private InviteResp invite;
    private LedgerResp ledger;
    private MemberResp member;
    private PersonResp person;
}
```

- [ ] In `join`, retain the locked ledger and invite checks; load the member; check capacity only for inactive/missing membership; current-read the account; create or version-restore the member; select linked people by ledger/account under lock; choose active then oldest deleted; create or version-update one person; increment quota only on admission. Build all nested DTOs from the committed-in-transaction state; copy legacy invitation fields from the nested invitation. Use only safe response fields, not entities or credentials.
- [ ] Assert the serialized response contract with full nested values and legacy `code`/`ledgerUuid`. A controller-level test must verify `InviteJoinResp.class` is used with the same POST path and request key. Confirm generic replay can deserialize a legacy flat InviteResp into InviteJoinResp.
- [ ] Run the focused tests and `mvn test`; commit as `feat: join invitations with linked participants`.

## Task 2: Flutter response parsing and immediate participant cache

**Files (Flutter repository):**
- Create `lib/core/models/invite_join_result.dart`
- Create `lib/core/services/invite_join_cache.dart`
- Modify `lib/core/repositories/invite_repository.dart`
- Modify `lib/core/services/sync_identity_resolver.dart` only if a local ledger lookup is needed
- Modify `lib/core/di/providers.dart`
- Modify `lib/features/ledgers/presentation/widgets/ledger_invite_widgets.dart`
- Modify `test/invite_repository_test.dart`
- Create `test/invite_join_cache_test.dart`
- Modify `test/ledger_invite_widgets_test.dart`

- [ ] Write failing tests for nested response caching: no second GET is necessary for a joined person; local/remote UUID mapping is preserved; a deleted linked person is restored under the original local UUID; identical nickname alone does not merge; membership and role reflect the API; repeat does not duplicate; same code new attempt gets a new key; malformed/mismatched nested identities never mutate; legacy response still restores hidden ledger; account/session switches reject stale results. Preserve unrelated pending edits and conflict snapshots.
- [ ] Run `flutter test test/invite_repository_test.dart test/invite_join_cache_test.dart test/ledger_invite_widgets_test.dart` and confirm failures for the missing behavior.
- [ ] Parse a typed result, distinguishing legacy flat responses from complete nested envelopes. Validate nonempty ledger/person/member/user UUIDs, positive versions, matching ledger/account identities, and active member status before writing. The existing public `Future<LedgerInvite> join(String code)` may stay unchanged so callers and test hooks remain compatible.

```dart
final operationKey = 'join-invite-v2-${const Uuid().v4()}';
final result = await _apiClient.post<InviteJoinResult>(
  '/api/invites/$normalizedCode/join',
  idempotencyKey: operationKey,
  fromJson: InviteJoinResult.fromJson,
);
```

- [ ] Keep storage logic in `InviteJoinCache`. Resolve local UUIDs through `SyncIdentityResolver`; save the person before attaching its UUID to the ledger; preserve other participant UUIDs and sort order. Existing live pending/conflicted business fields remain local; only joined access, role/member metadata, and new identity association are authoritative. A hidden access record can be restored. New ledger is cloud-managed and account-owned. Never use person display name for identity.
- [ ] Inject TokenStore and identity/cache dependencies in `inviteRepositoryProvider`. Compare the captured account and token against the active session before applying the response. Return a normal actionable error on a changed session, with no local restoration.
- [ ] After join, invalidate both ledger/statistics/sync state and the existing cached/visible people providers. Add a widget regression demonstrating that a mounted person consumer sees the returned participant after join; keep existing navigation/loading/error behavior.
- [ ] Run focused tests, `flutter analyze`, and `flutter test`; commit as `feat: cache joined participants before refresh`.

## Task 3: Cross-contract verification and delivery

**Files:**
- Flutter `docs/product-features.md`
- Flutter `docs/project-handoff.md`
- API `README.md`

- [ ] Check an API-generated join response against Flutter's real parser/cache integration test. Confirm participant identity, role, version, and ledger are usable while subsequent GET requests fail.
- [ ] Record exactly this completed slice and list remaining stage-4 role UI/member UI and stage-5 statistics work. Document additive API compatibility and fresh join-attempt keys; do not claim all-chain completion.
- [ ] Run API `mvn test`; Flutter `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, and `flutter build web`; run `git diff --check` in both repositories.
- [ ] Complete spec compliance review, then code-quality review. Fix actionable problems and rerun regression tests before integration.
- [ ] As previously requested, merge verified branches locally to each `master`, rerun tests on the merged state, and remove only the owned, clean worktrees after path validation. Do not push or deploy.
