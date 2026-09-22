# Account-Scoped Offline Ledgers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate account-owned local ledger data while keeping never-synced guest ledgers visible, add explicit whole-ledger claiming, and ship the verified Flutter web deployment plus a small arm64 APK.

**Architecture:** Keep a device-level `guest` scope and an `account/<accountUuid>` scope. `DatabaseService` will read the guest scope plus the active account scope, route writes using persisted local ownership metadata, and migrate the existing global cache conservatively. Cloud access remains server-authoritative; an explicit sync action moves a guest ledger into the current account scope before using the existing idempotent ledger/person/transaction upload pipeline.

**Tech Stack:** Flutter/Dart, Riverpod, SharedPreferences, Dio, existing repository/sync services, Flutter widget/unit tests, Flutter web and Android release builds.

---

## Task 1: Add local scope primitives and scoped storage

**Files:**
- Create: `lib/core/database/local_data_scope.dart`
- Modify: `lib/core/models/ledger.dart`
- Modify: `lib/core/models/person.dart`
- Modify: `lib/core/models/transaction_record.dart`
- Modify: `lib/core/database/database_service.dart`
- Test: `test/database_scope_test.dart`

- [ ] **Step 1: Write failing scope tests**

Create tests that use `SharedPreferences.setMockInitialValues({})` and verify:

```dart
final guest = DatabaseService(scope: LocalDataScope.guest);
final accountA = DatabaseService(
  scope: LocalDataScope.account('account-a'),
);
final accountB = DatabaseService(
  scope: LocalDataScope.account('account-b'),
);

await guest.saveLedger(localLedger('guest-ledger'));
await accountA.saveLedger(localLedger('a-ledger'));

expect((await accountA.getAllLedgers()).map((item) => item.uuid),
    containsAll(<String>['guest-ledger', 'a-ledger']));
expect((await accountB.getAllLedgers()).map((item) => item.uuid),
    contains('guest-ledger'));
expect((await accountB.getAllLedgers()).map((item) => item.uuid),
    isNot(contains('a-ledger')));
```

Also test that a person and transaction attached to an account ledger are absent from another account, while guest records remain visible to both accounts.

- [ ] **Step 2: Run the new tests and verify the missing-scope failure**

Run:

```bash
/Users/simon/enviroment/flutter/bin/flutter --no-version-check test test/database_scope_test.dart
```

Expected: FAIL because `LocalDataScope`, scoped storage, and local ownership fields do not exist yet.

- [ ] **Step 3: Implement scope metadata and storage routing**

Add `LocalDataScope` with `guest` and `account(String uuid)` constructors and a stable storage key. Add nullable `localAccountUuid` to `Ledger`, `Person`, and `TransactionRecord`; add `claimPending` to `Ledger`.

Change `DatabaseService` to accept `LocalDataScope scope`, use versioned keys under `local_store.guest.*` and `local_store.account.<uuid>.*`, and expose the active account scope while reading:

```dart
class DatabaseService {
  DatabaseService({this.scope = LocalDataScope.guest});

  final LocalDataScope scope;

  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false});
  Future<void> saveLedger(Ledger ledger);
  Future<void> claimLedger(String uuid, String accountUuid);
  Future<void> releaseLedgerClaim(String uuid);
}
```

The active-account read methods must merge guest records with the current account records. Writes must route account-owned records to the account key and guest records to the guest key. Person and transaction writes must derive their local account from the referenced ledger when their metadata is absent.

Implement `claimLedger` as one local operation: copy the ledger, its people, and its transactions from guest storage into the target account storage, set `localAccountUuid` and `claimPending`, then remove the guest copies. `releaseLedgerClaim` moves the complete set back to guest storage. Keep remote UUID mappings and local UUID references unchanged during this move.

Update JSON serialization for all new fields and preserve soft-delete behavior.

- [ ] **Step 4: Add conservative v1 migration**

Extend `DatabaseService.init()` with a one-time migration marker. Read the existing `local_store.*.v1` records, assign ledgers with a known `cacheOwnerUserUuid` to that account scope, and assign local-only or ambiguous records to guest scope. Move people and transactions by ledger reference; leave unresolvable records in guest scope. Never infer ownership from nickname or avatar.

- [ ] **Step 5: Run scope tests and the existing database tests**

Run:

```bash
/Users/simon/enviroment/flutter/bin/flutter --no-version-check test test/database_scope_test.dart test/database_service_test.dart
```

Expected: all selected tests pass with zero failures.

## Task 2: Make dependency providers and local profiles scope-aware

**Files:**
- Modify: `lib/core/di/providers.dart`
- Modify: `lib/core/preferences/local_profile_store.dart`
- Modify: `lib/core/services/conflict_store.dart`
- Modify: `lib/core/services/sync_overview_service.dart`
- Modify: `lib/core/services/profile_projection_service.dart`
- Modify: `lib/core/services/profile_sync_service.dart`
- Modify: `lib/core/services/sync_identity_resolver.dart`
- Test: `test/local_profile_store_test.dart`
- Test: `test/profile_sync_service_test.dart`
- Test: `test/profile_projection_service_test.dart`

- [ ] **Step 1: Write failing account-switch and identity tests**

Cover these behaviors:

```dart
test('profile storage is independent per account', () async {
  final guest = LocalProfileStore(scope: LocalDataScope.guest);
  final accountA = LocalProfileStore(
    scope: LocalDataScope.account('account-a'),
  );
  final accountB = LocalProfileStore(
    scope: LocalDataScope.account('account-b'),
  );
  // Save different profiles and assert each scope reads its own profile.
});

test('profile projection never matches a person by nickname or avatar', () async {
  // Seed a guest person with the previous profile's display values.
  // Apply account A's profile and assert the guest person is unchanged.
});
```

- [ ] **Step 2: Implement scope-aware providers and profile storage**

Add an active account scope provider derived from the existing authenticated account UUID. Make `databaseProvider`, `localProfileStoreProvider`, `conflictStoreProvider`, and `syncOverviewServiceProvider` use that active scope while preserving existing provider overrides in tests.

Change profile and conflict keys to include the scope. Keep conflicts filtered by account UUID as a second safety check. Scope the last-successful-sync timestamp as well.

Remove nickname/avatar heuristics from `ProfileProjectionService`. Only update a person when its `localAccountUuid` matches the current account or its `linkedUserUuid` exactly matches the current account. A guest person must not be rewritten by an account profile.

Ensure `SyncIdentityResolver` resolves only records visible in the active scoped database and never crosses account storage boundaries.

- [ ] **Step 3: Run focused provider/profile tests**

Run:

```bash
/Users/simon/enviroment/flutter/bin/flutter --no-version-check test test/local_profile_store_test.dart test/profile_sync_service_test.dart test/profile_projection_service_test.dart
```

Expected: all selected tests pass, including the new identity-isolation regression tests.

## Task 3: Implement explicit guest-ledger claiming and scoped remote sync

**Files:**
- Modify: `lib/core/repositories/ledger_repository.dart`
- Modify: `lib/core/repositories/person_repository.dart`
- Modify: `lib/core/repositories/transaction_repository.dart`
- Modify: `lib/core/services/sync_coordinator.dart`
- Modify: `lib/features/ledgers/presentation/providers/ledger_provider.dart`
- Test: `test/remote_ledger_repository_test.dart`
- Test: `test/sync_coordinator_test.dart`

- [ ] **Step 1: Write failing claim tests**

Add tests that assert:

```dart
test('logged-in sync claims a guest ledger before uploading', () async {
  // Seed a guest ledger with people and a transaction.
  // Call the explicit claim/sync operation as account A.
  // Assert the local records now carry account A scope and remote IDs are retained.
});

test('failed claim remains reserved for the original account', () async {
  // Force the remote adapter to fail after the claim starts.
  // Assert B cannot read the claiming ledger and A can retry it.
});
```

- [ ] **Step 2: Change logged-in local creation to remain guest-local**

`RemoteLedgerRepository.createLedgerWithPeople` must save a new ledger and its people in guest scope without setting `uploadRequested` or starting an automatic upload. This makes sync an explicit user action. Existing cloud-managed ledgers continue to use the current pending-write path.

- [ ] **Step 3: Add the explicit claim operation**

Extend `LedgerRepository` with:

```dart
Future<void> claimLedger(String uuid);
```

Implement it in `RemoteLedgerRepository` by reading the current account UUID, calling `DatabaseService.claimLedger`, and then marking the moved ledger `uploadRequested`, `pendingSync`, and `claimPending`. `syncPendingWrites` uploads only explicitly claimed account records; `syncAllPending` must never auto-claim a guest ledger.

On successful remote creation and transaction/person upload, mark `claimPending = false` and `cloudPolicy = cloudManaged`. On failure, keep the account reservation and retry metadata.

When remote ledgers, people, and transactions are cached, assign their `localAccountUuid` to the current account before saving. Keep the server-provided UUIDs and names authoritative.

- [ ] **Step 4: Route per-ledger sync through claim when needed**

Update `SyncCoordinator.syncLedger` to detect a guest local ledger while an account is active, call `claimLedger`, and then run the existing ledger/person/transaction sync sequence. A plain `syncAllPending` call must continue to process only already-claimed account data.

- [ ] **Step 5: Run focused repository/sync tests**

Run:

```bash
/Users/simon/enviroment/flutter/bin/flutter --no-version-check test test/remote_ledger_repository_test.dart test/remote_transaction_repository_test.dart test/sync_coordinator_test.dart
```

Expected: all selected tests pass, including no duplicate upload after retry.

## Task 4: Expose the new behavior in the ledger UI

**Files:**
- Modify: `lib/features/home/presentation/screens/home_page.dart`
- Modify: `lib/features/ledgers/presentation/widgets/ledger_list_tab.dart`
- Modify: `lib/features/auth/presentation/widgets/account_tab.dart`
- Test: `test/ledger_list_tab_test.dart`
- Test: `test/home_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add widget coverage for:

- a logged-in user sees a guest ledger labeled `本地账本 · 尚未同步`;
- tapping its sync action shows an ownership confirmation;
- confirming moves the ledger into the active account and refreshes the list;
- account B cannot see A's claimed ledger after provider invalidation;
- a shared ledger keeps its original member/person display values.

- [ ] **Step 2: Add explicit guest-ledger status and sync action**

Update the ledger card to distinguish guest-local, claiming, failed, and cloud-managed states. When logged in, show the sync action for a guest ledger even when it has no pending cloud write. Keep automatic background sync disabled for unclaimed guest ledgers.

Use confirmation text equivalent to:

```text
同步后，这个账本将归属当前账号，其他账号将无法继续查看。
```

If the user is logged out, do not offer the claim action; keep the ledger editable offline.

- [ ] **Step 3: Refresh providers on scope transitions**

After login, logout, session expiry, claim success, claim failure, and claim cancellation, invalidate ledger, person, transaction, stats, conflict, and sync-overview providers. Ensure no previous account list remains visible while the new scope is loading.

- [ ] **Step 4: Run focused widget tests**

Run:

```bash
/Users/simon/enviroment/flutter/bin/flutter --no-version-check test test/ledger_list_tab_test.dart test/home_page_test.dart
```

Expected: all selected tests pass with the new guest/account visibility assertions.

## Task 5: Complete migration and regression coverage

**Files:**
- Modify: `test/database_service_test.dart`
- Modify: `test/conflict_provider_refresh_test.dart`
- Modify: `test/profile_sync_service_test.dart`
- Modify: `test/remote_transaction_repository_test.dart`
- Create or modify: `test/account_scope_integration_test.dart`

- [ ] **Step 1: Add end-to-end scope scenarios**

Exercise this sequence with mock storage and remote adapters:

```text
guest creates ledger
→ login A and view guest ledger
→ claim/sync as A
→ logout
→ login B and verify A ledger is absent
→ create another guest ledger
→ login A and verify both A ledger and guest ledger are visible
→ claim second ledger as A
```

- [ ] **Step 2: Add migration scenarios**

Seed the old v1 keys with one ledger carrying `cacheOwnerUserUuid`, one local-only ledger, people, and transactions. Run initialization twice and assert:

- the owned ledger is only in the matching account scope;
- the local-only ledger is in guest scope;
- references and UUID mappings are unchanged;
- no duplicate records are created on the second run.

- [ ] **Step 3: Run the complete Flutter test suite**

Run:

```bash
/Users/simon/enviroment/flutter/bin/flutter --no-version-check test
```

Expected: all tests pass with zero failures.

## Task 6: Verify, commit, push, deploy, and package Android

**Files:**
- No additional source files; use the repository scripts and build outputs.

- [ ] **Step 1: Run formatting, analysis, and build checks**

Run:

```bash
/Users/simon/enviroment/flutter/bin/dart format lib test
/Users/simon/enviroment/flutter/bin/flutter --no-version-check analyze
/Users/simon/enviroment/flutter/bin/flutter --no-version-check test
```

Expected: formatting makes no unintended changes, analyze reports zero errors, and the full test suite passes.

- [ ] **Step 2: Commit only implementation files**

Use the bundled Git runtime and verify `git diff --cached --check` before committing. Do not stage the existing `analysis_options.yaml` change, `web.tar.gz`, `app.tar.gz`, or generated APKs.

Commit message:

```text
feat: isolate offline ledgers by account
```

- [ ] **Step 3: Push Flutter master**

Use the authenticated GitHub SSH-over-443 command already configured for this workspace:

```bash
GIT_SSH_COMMAND='ssh -o HostName=ssh.github.com -p 443 -i ~/.ssh/id_rsa -o IdentitiesOnly=yes' git push origin master
```

Verify `git ls-remote origin refs/heads/master` matches the local commit.

- [ ] **Step 4: Build and deploy the Flutter web app**

Run from `/Users/simon/workplace/projects/simon_ledger`:

```bash
bash deploy_web.sh
curl -fsSI --max-time 20 https://ledger.simon996.com/
```

Expected: the deployment script exits zero and the production site returns HTTP 200.

- [ ] **Step 5: Build the smallest practical APK**

Build the arm64 release split, which avoids bundling unsupported ABIs into the delivered APK:

```bash
/Users/simon/enviroment/flutter/bin/flutter --no-version-check build apk --release --split-per-abi --target-platform android-arm64
```

Verify the output exists and report its size:

```bash
ls -lh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The APK is an untracked build artifact and will be delivered by its absolute workspace path without committing it.
