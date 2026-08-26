# Flutter Optimistic Conflict Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为账户资料、账本、成员、参与人和流水建立 Flutter 端统一版本模型、结构化 HTTP 409 处理、持久化冲突队列和逐项人工确认界面，并保证冲突实体停止自动重试、其他数据继续同步。

**Architecture:** API 层保留失败响应的结构化 `data`，`ConflictCoordinator` 将远端冲突载荷与本机业务快照组合后写入独立 `ConflictStore`。Repository 仍先写本地；网络失败继续保持 `pendingSync`，409 则清除该实体的自动重试标记并交给冲突中心。冲突解决由协调器直接使用 API 最新版本提交或应用远端快照，避免 Repository 与协调器循环依赖。

**Tech Stack:** Flutter 3、Dart 3.11、Riverpod 3、Dio 5、SharedPreferences、Material 3、flutter_test

---

## Scope and invariants

本计划只实现全链路设计第 14 节的“Flutter 冲突基础”和“冲突 UI”。邀请角色、成员管理、邀请加入自动参与人和云端统计在后续独立计划中完成。

- 旧缓存缺少版本时按 `1` 读取，不能清空任何已有缓存。
- 冲突键为 `entityType + remoteUuid`；同一实体的新 409 替换原记录的远端版本和快照。
- 快照只含业务字段，不能保存 Token、密码、密码 hash、邮箱或手机号。
- 409 实体停止普通同步重试；其他实体和其他账本继续同步。
- “使用云端”可离线立即完成；“保留本机”离线进入 `queuedLocal`，联网后重试。
- 再次 409 更新同一冲突并回到 `unresolved`，不能静默覆盖。
- UI 不提供批量覆盖；处理成功后进入下一条。
- 删除、恢复或覆盖云端删除状态前必须二次确认。

## File map

**New domain files**

- `lib/core/models/conflict_record.dart`: 冲突枚举、远端 409 载荷、持久化记录及 JSON。
- `lib/core/services/conflict_store.dart`: `local_store.conflicts.v1` 的串行读写与去重。
- `lib/core/services/conflict_snapshot_codec.dart`: 五类实体的安全快照、API 请求和本地应用。
- `lib/core/services/conflict_coordinator.dart`: 捕获、使用云端、保留本机、离线排队和再次冲突。
- `lib/features/conflicts/presentation/screens/conflict_center_page.dart`: 分组列表和空状态。
- `lib/features/conflicts/presentation/screens/conflict_detail_page.dart`: 逐字段比较与两个明确选择。
- `lib/features/conflicts/presentation/widgets/conflict_entry_widgets.dart`: 全局提示和账本徽标。

**Modified integration files**

- `lib/core/models/{ledger,person,transaction_record,local_profile}.dart`
- `lib/core/preferences/local_profile_store.dart`
- `lib/core/database/database_service.dart`
- `lib/core/network/{api_result,api_exception,api_client}.dart`
- `lib/core/repositories/{auth,ledger,person,transaction}_repository.dart`
- `lib/core/services/{profile_sync_service,sync_overview_service}.dart`
- `lib/core/di/providers.dart`
- `lib/features/home/presentation/screens/home_page.dart`
- `lib/features/auth/presentation/widgets/account_tab.dart`
- `lib/features/ledgers/presentation/widgets/ledger_list_tab.dart`

## Task 1: Persist entity versions with legacy compatibility

**Files:**

- Modify: `lib/core/models/ledger.dart`
- Modify: `lib/core/models/person.dart`
- Modify: `lib/core/models/transaction_record.dart`
- Modify: `lib/core/models/local_profile.dart`
- Modify: `lib/core/repositories/auth_repository.dart`
- Modify: `lib/core/preferences/local_profile_store.dart`
- Modify: `lib/core/database/database_service.dart`
- Test: `test/database_service_test.dart`
- Test: `test/local_profile_store_test.dart`
- Test: `test/api_result_test.dart`

- [ ] **Step 1: Write failing legacy-cache and response tests**

Add tests proving absent JSON versions become `1`, explicit versions round-trip, `AuthUser.fromJson` reads `version`, and `LocalProfileStore` preserves `remoteVersion`:

```dart
test('legacy cache defaults all mutable entity versions to one', () async {
  SharedPreferences.setMockInitialValues({
    'local_store.ledgers.v1': jsonEncode([{
      'uuid': 'ledger-1',
      'name': '旧账本',
      'baseCurrencyCode': 'CNY',
    }]),
    'local_store.people.v1': jsonEncode([{
      'uuid': 'person-1',
      'name': '旧参与人',
    }]),
    'local_store.transactions.v1': jsonEncode([{
      'uuid': 'transaction-1',
      'ledgerUuid': 'ledger-1',
      'amount': 12,
      'currencyCode': 'CNY',
      'category': '餐饮',
      'createdAt': '2026-08-26T08:00:00.000',
    }]),
  });

  final database = DatabaseService();
  expect((await database.getAllLedgers()).single.version, 1);
  expect((await database.getAllPeople()).single.version, 1);
  expect(
    (await database.getTransactionsForLedger('ledger-1')).single.version,
    1,
  );
});
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```powershell
flutter test test/database_service_test.dart test/local_profile_store_test.dart test/api_result_test.dart
```

Expected: compilation fails because ledger/person/profile/member versions do not exist and transaction version is nullable.

- [ ] **Step 3: Add non-null version fields**

Use a non-null default consistently:

```dart
// Ledger, Person, TransactionRecord
int version = 1;

// LedgerMemberSummary constructor/field
this.version = 1,
final int version;

// LocalProfile constructor/field/copyWith
this.remoteVersion = 1,
final int remoteVersion;

// AuthUser constructor/field/fromJson
this.version = 1,
final int version;
version: (map['version'] as num?)?.toInt() ?? 1,
```

`AuthRepository.updateProfile` must accept the submitted version:

```dart
Future<AuthUser> updateProfile({
  required String nickname,
  String? avatar,
  required int version,
});
```

- [ ] **Step 4: Serialize versions without destructive migration**

Add `version` to ledger/person/member/transaction JSON and use `(json['version'] as num?)?.toInt() ?? 1`. Add `local_profile.remote_version.v1` to `LocalProfileStore`; missing value reads as `1`.

- [ ] **Step 5: Run tests and commit**

```powershell
dart format lib test
flutter test test/database_service_test.dart test/local_profile_store_test.dart test/api_result_test.dart
git add lib/core test/database_service_test.dart test/local_profile_store_test.dart test/api_result_test.dart
git commit -m "feat: persist optimistic entity versions"
```

## Task 2: Preserve structured HTTP conflict data

**Files:**

- Create: `lib/core/models/conflict_record.dart`
- Modify: `lib/core/network/api_result.dart`
- Modify: `lib/core/network/api_exception.dart`
- Modify: `lib/core/network/api_client.dart`
- Create: `test/api_client_conflict_test.dart`
- Modify: `test/api_result_test.dart`

- [ ] **Step 1: Write failing API parsing tests**

Use a Dio adapter returning HTTP 409 and assert no message matching is needed:

```dart
expect(
  client.put<Object?>('/api/auth/me', data: {'version': 2}),
  throwsA(
    isA<ApiException>()
        .having((error) => error.isConflict, 'isConflict', isTrue)
        .having(
          (error) => error.conflict?.remoteVersion,
          'remoteVersion',
          3,
        ),
  ),
);
```

Also test malformed `data` remains a normal `ApiException` rather than crashing.

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/api_result_test.dart test/api_client_conflict_test.dart
```

Expected: `ApiException` has no structured payload or `isConflict`.

- [ ] **Step 3: Add exact conflict types**

```dart
enum ConflictEntityType { profile, ledger, member, person, transaction }

class ApiConflictPayload {
  const ApiConflictPayload({
    required this.entityType,
    required this.entityUuid,
    required this.submittedVersion,
    required this.remoteVersion,
    required this.remoteDeleted,
    required this.remoteSnapshot,
  });

  factory ApiConflictPayload.fromJson(Object? json) { /* strict map parsing */ }
}
```

Extend `ApiException`:

```dart
final Object? data;
final ApiConflictPayload? conflict;
bool get isConflict => code == 409001 && statusCode == 409 && conflict != null;
```

`ApiResult` keeps `rawData` even on failure. Both Dio error handling branches and `_parseResponse` pass raw `data` into `ApiException`; parsing failures set `conflict=null`.

- [ ] **Step 4: Run tests and commit**

```powershell
dart format lib test
flutter test test/api_result_test.dart test/api_client_conflict_test.dart
git add lib/core/models/conflict_record.dart lib/core/network test/api_result_test.dart test/api_client_conflict_test.dart
git commit -m "feat: parse structured api conflicts"
```

## Task 3: Add a durable de-duplicating conflict store

**Files:**

- Modify: `lib/core/models/conflict_record.dart`
- Create: `lib/core/services/conflict_store.dart`
- Create: `test/conflict_store_test.dart`

- [ ] **Step 1: Write failing store tests**

Cover round-trip, oldest-first order, same-entity replacement, state transitions and removal:

```dart
test('upsert replaces the visible conflict for the same remote entity', () async {
  final store = ConflictStore();
  await store.upsert(conflict(remoteVersion: 2));
  await store.upsert(conflict(remoteVersion: 3));

  final records = await store.readAll();
  expect(records, hasLength(1));
  expect(records.single.remoteVersion, 3);
});
```

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/conflict_store_test.dart
```

- [ ] **Step 3: Implement record and store**

```dart
enum ConflictOperation { update, delete, restore }
enum ConflictState { unresolved, queuedLocal, resolving, failed }

class ConflictRecord {
  // id, entityType, ledgerUuid, localUuid, remoteUuid, operation,
  // baseVersion, remoteVersion, localSnapshot, remoteSnapshot,
  // remoteDeleted, detectedAt, state, error
}
```

`ConflictStore` uses the exact key `local_store.conflicts.v1`. All mutations serialize through one internal future chain. `upsert` compares `entityType.name` and `remoteUuid`, preserves the original `id/detectedAt`, replaces remote data, and returns state to `unresolved`.

- [ ] **Step 4: Run tests and commit**

```powershell
dart format lib test
flutter test test/conflict_store_test.dart
git add lib/core/models/conflict_record.dart lib/core/services/conflict_store.dart test/conflict_store_test.dart
git commit -m "feat: persist unresolved data conflicts"
```

## Task 4: Encode safe snapshots and apply remote choices

**Files:**

- Create: `lib/core/services/conflict_snapshot_codec.dart`
- Create: `test/conflict_snapshot_codec_test.dart`

- [ ] **Step 1: Write failing codec tests**

Assert snapshots contain every user-visible field, preserve local UUID mappings, and exclude sensitive profile fields:

```dart
test('profile snapshot contains no account credentials', () {
  final snapshot = ConflictSnapshotCodec.profile(
    const LocalProfile(nickname: '本机昵称', avatarIcon: 'star'),
    accountUuid: 'user-1',
  );
  expect(snapshot.keys, containsAll(['uuid', 'nickname', 'avatar', 'version']));
  expect(snapshot.keys, isNot(contains('email')));
  expect(snapshot.keys, isNot(contains('phone')));
  expect(snapshot.keys, isNot(contains('token')));
});
```

Add tests for ledger/member/person/transaction request maps and remote snapshot application.

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/conflict_snapshot_codec_test.dart
```

- [ ] **Step 3: Implement one codec boundary**

Expose named methods rather than scattered maps:

```dart
Map<String, Object?> profileSnapshot(...);
Map<String, Object?> ledgerSnapshot(Ledger value);
Map<String, Object?> memberSnapshot(LedgerMemberSummary value);
Map<String, Object?> personSnapshot(Person value);
Map<String, Object?> transactionSnapshot(TransactionRecord value);
Map<String, Object?> requestData(ConflictRecord record, int version);
Future<void> applyRemote(ConflictRecord record);
Future<void> applyMutationVersion(ConflictRecord record, int version);
```

The codec receives `DatabaseService` and `LocalProfileStore`. Applying a remote object retains the cached local ledger UUID and `syncedRemoteUuid`, retains a local transaction's `ledgerUuid/clientOperationId`, maps remote person UUIDs through `SyncIdentityResolver`, clears `pendingSync/syncError`, and applies `remoteDeleted`.

- [ ] **Step 4: Run tests and commit**

```powershell
dart format lib test
flutter test test/conflict_snapshot_codec_test.dart
git add lib/core/services/conflict_snapshot_codec.dart test/conflict_snapshot_codec_test.dart
git commit -m "feat: encode and apply conflict snapshots"
```

## Task 5: Coordinate capture and explicit resolution

**Files:**

- Create: `lib/core/services/conflict_coordinator.dart`
- Create: `test/conflict_coordinator_test.dart`

- [ ] **Step 1: Write failing coordinator tests**

Cover capture, cloud choice, local choice, network queue, queued retry, conflict refresh and non-conflict failure:

```dart
test('second conflict updates the existing record and requires confirmation again', () async {
  await coordinator.capture(
    error: conflictError(remoteVersion: 2),
    operation: ConflictOperation.update,
    ledgerUuid: 'ledger-1',
    localUuid: 'transaction-1',
    localSnapshot: localTransactionSnapshot,
  );
  gateway.nextError = conflictError(remoteVersion: 3);

  await coordinator.keepLocal((await store.readAll()).single.id);

  final record = (await store.readAll()).single;
  expect(record.remoteVersion, 3);
  expect(record.state, ConflictState.unresolved);
});
```

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/conflict_coordinator_test.dart
```

- [ ] **Step 3: Implement resolver gateway and coordinator**

Define an injectable gateway for testability:

```dart
abstract interface class ConflictResolutionGateway {
  Future<ConflictMutationResult> submit(ConflictRecord record);
}

class ApiConflictResolutionGateway implements ConflictResolutionGateway {
  // Select PUT/DELETE/POST restore from entityType, operation and remoteDeleted.
  // Every request uses record.remoteVersion and a stable idempotency key.
}
```

Coordinator behavior:

```dart
Future<bool> capture({...});
Future<void> useRemote(String id);
Future<ConflictResolutionOutcome> keepLocal(String id);
Future<void> retryQueuedLocal();
```

`useRemote` applies the saved remote snapshot without network. `keepLocal` sets `resolving`, submits against `remoteVersion`, applies returned object/version and removes on success; network failure becomes `queuedLocal`; another 409 upserts the latest remote payload as `unresolved`; permission/auth/validation failures become `failed` with user-readable text.

- [ ] **Step 4: Run tests and commit**

```powershell
dart format lib test
flutter test test/conflict_coordinator_test.dart
git add lib/core/services/conflict_coordinator.dart test/conflict_coordinator_test.dart
git commit -m "feat: resolve conflicts explicitly"
```

## Task 6: Capture conflicts in profile and repositories

**Files:**

- Modify: `lib/core/services/profile_sync_service.dart`
- Modify: `lib/core/repositories/auth_repository.dart`
- Modify: `lib/core/repositories/ledger_repository.dart`
- Modify: `lib/core/repositories/person_repository.dart`
- Modify: `lib/core/repositories/transaction_repository.dart`
- Modify: `lib/core/services/sync_coordinator.dart`
- Test: `test/profile_sync_service_test.dart`
- Test: `test/remote_cache_repository_test.dart`
- Test: `test/remote_transaction_repository_test.dart`
- Test: `test/sync_coordinator_test.dart`

- [ ] **Step 1: Write failing repository tests**

For profile, ledger, person and transaction, return structured 409 and assert:

```dart
expect(local.pendingSync, isFalse);
expect(local.syncError, isNull);
expect(await conflictStore.readAll(), hasLength(1));
```

Add a sync test with two pending transactions where the first conflicts and the second succeeds; expected `synced == 1`, one conflict, no retry error.

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/profile_sync_service_test.dart test/remote_cache_repository_test.dart test/remote_transaction_repository_test.dart test/sync_coordinator_test.dart
```

- [ ] **Step 3: Send versions on every mutation**

- Profile PUT includes `version: profile.remoteVersion`.
- Ledger PUT/DELETE/leave includes `ledger.version` and saves success version.
- Person PUT/DELETE includes `person.version` and saves success version.
- Transaction already sends update/delete version; replace static in-memory version maps with the persisted non-null model version.
- All response parsers read versions, including `LedgerMemberSummary`.

- [ ] **Step 4: Capture only structured 409**

Inject `ConflictCoordinator` into remote repositories and `ProfileSyncService`. In each catch:

```dart
if (error is ApiException && error.isConflict) {
  await _conflicts.capture(
    error: error,
    operation: operation,
    ledgerUuid: ledgerUuid,
    localUuid: entity.uuid,
    localSnapshot: _codec.transactionSnapshot(entity),
  );
  entity
    ..pendingSync = false
    ..syncError = null;
  await _db.saveTransaction(entity);
  return;
}
```

Do not stop the pending loop after a conflict. Network errors retain existing behavior. Remove only the conflicted entity from automatic retry by clearing its `pendingSync` after the conflict has been durably stored.

- [ ] **Step 5: Run tests and commit**

```powershell
dart format lib test
flutter test test/profile_sync_service_test.dart test/remote_cache_repository_test.dart test/remote_transaction_repository_test.dart test/sync_coordinator_test.dart
git add lib/core/repositories lib/core/services test
git commit -m "feat: route stale writes to conflict center"
```

## Task 7: Expose conflict state through Riverpod and sync overview

**Files:**

- Modify: `lib/core/di/providers.dart`
- Modify: `lib/core/services/sync_overview_service.dart`
- Modify: `lib/core/services/sync_coordinator.dart`
- Test: `test/sync_overview_service_test.dart`

- [ ] **Step 1: Write failing provider/overview tests**

Add `conflictCount` and ledger counts to `SyncOverview`, proving conflicts are separate from failed and pending counts.

```dart
expect(overview.conflictCount, 2);
expect(overview.pendingCount, 1);
expect(overview.failedCount, 0);
expect(overview.conflictsByLedger['ledger-1'], 1);
```

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/sync_overview_service_test.dart
```

- [ ] **Step 3: Wire providers without cycles**

Add providers for `ConflictStore`, `ConflictSnapshotCodec`, `ConflictResolutionGateway`, `ConflictCoordinator`, `conflictRecordsProvider`, `conflictCountProvider` and `ledgerConflictCountProvider`. Repositories watch the coordinator; the coordinator watches only API/database/profile/token/identity dependencies, never repositories.

`SyncOverviewService` reads `ConflictStore`, reports conflict counts independently, and keeps `failedCount` for non-conflict failures only. Network-restored sync invokes `retryQueuedLocal()` before normal entity synchronization.

- [ ] **Step 4: Run tests and commit**

```powershell
dart format lib test
flutter test test/sync_overview_service_test.dart test/sync_coordinator_test.dart
git add lib/core/di/providers.dart lib/core/services test
git commit -m "feat: expose conflict sync state"
```

## Task 8: Build the non-blocking conflict entry and grouped list

**Files:**

- Create: `lib/features/conflicts/presentation/widgets/conflict_entry_widgets.dart`
- Create: `lib/features/conflicts/presentation/screens/conflict_center_page.dart`
- Modify: `lib/features/home/presentation/screens/home_page.dart`
- Modify: `lib/features/auth/presentation/widgets/account_tab.dart`
- Modify: `lib/features/ledgers/presentation/widgets/ledger_list_tab.dart`
- Create: `test/conflict_entry_widgets_test.dart`
- Create: `test/conflict_center_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Cover the top notice, account sync entry, per-ledger badge, grouping and oldest-first list:

```dart
expect(find.text('有 2 项数据需要确认'), findsOneWidget);
expect(find.text('账户资料'), findsOneWidget);
expect(find.text('家庭账本'), findsOneWidget);
expect(find.text('冲突 1 项'), findsOneWidget);
```

Assert no conflict entry is shown for count zero.

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/conflict_entry_widgets_test.dart test/conflict_center_page_test.dart
```

- [ ] **Step 3: Implement Apple Calm entry surfaces**

- Home uses a compact `AppNotice`-style strip above the current tab, not a modal.
- Account sync center adds a single “数据冲突 N” row with “逐项处理”.
- Ledger card adds an independent `冲突 N 项` chip; it does not replace local/cloud/shared type or pending status.
- Conflict center groups profile separately and ledger records by cached ledger name; loading uses `AppLoadingState`, empty uses `AppEmptyState`, failed reads use friendly inline error.

Use `AppTheme`/`ColorScheme`, radii 12/24/28, `AppMotion` opacity/transform transitions, and no new raw business colors or emoji.

- [ ] **Step 4: Run tests and commit**

```powershell
dart format lib test
flutter test test/conflict_entry_widgets_test.dart test/conflict_center_page_test.dart test/home_page_test.dart test/ledger_list_tab_test.dart test/account_sync_center_content_test.dart
git add lib/features lib/core/di/providers.dart test
git commit -m "feat: surface unresolved conflicts"
```

## Task 9: Add field-level comparison and explicit choices

**Files:**

- Create: `lib/features/conflicts/presentation/screens/conflict_detail_page.dart`
- Create: `test/conflict_detail_page_test.dart`

- [ ] **Step 1: Write failing detail tests**

Cover changed-only emphasis, collapsed identical fields, fixed actions, destructive confirmation, offline local queue, success advance and repeated-conflict stay:

```dart
expect(find.text('本机版本'), findsOneWidget);
expect(find.text('云端版本'), findsOneWidget);
expect(find.text('金额'), findsOneWidget);
expect(find.text('备注'), findsNothing); // identical field collapsed
expect(find.widgetWithText(FilledButton, '保留本机版本'), findsOneWidget);
expect(find.widgetWithText(OutlinedButton, '使用云端版本'), findsOneWidget);
```

- [ ] **Step 2: Run and confirm RED**

```powershell
flutter test test/conflict_detail_page_test.dart
```

- [ ] **Step 3: Implement deterministic field descriptors**

Use an entity-specific ordered field list:

```dart
profile: nickname, avatar
ledger: name, baseCurrencyCode, exchangeRateToCny, deleted
member: nickname, role, status, deleted
person: name, avatar, linkedUserUuid, deleted
transaction: type, amount, currencyCode, category, happenedAt,
             payerPersonUuid, personUuids, note, deleted
```

Mobile lays local and cloud values vertically. Changed fields use a quiet primary tint; identical fields are behind “查看相同字段”. Bottom actions stay inside `SafeArea`. Destructive state changes use a centered confirmation dialog whose action text is “覆盖云端并恢复”“确认删除” or “使用云端删除结果”, never generic “确定”.

- [ ] **Step 4: Run tests and commit**

```powershell
dart format lib test
flutter test test/conflict_detail_page_test.dart test/conflict_center_page_test.dart
git add lib/features/conflicts test
git commit -m "feat: resolve conflicts item by item"
```

## Task 10: Full verification and integration

**Files:**

- Modify: `docs/product-features.md`
- Modify: `docs/project-handoff.md`

- [ ] **Step 1: Add a cross-entity integration test**

Create `test/conflict_full_chain_test.dart`: seed two pending entities, return 409 for one and success for the other, reopen `ConflictStore`, use remote offline, and assert the conflict disappears while the successful entity remains synced.

- [ ] **Step 2: Run focused integration test**

```powershell
flutter test test/conflict_full_chain_test.dart
```

- [ ] **Step 3: Update operational documentation**

Document the conflict entry, two choices, queued-local state and “409 does not equal generic sync failure”. Keep the full product rules in the existing design rather than duplicating them.

- [ ] **Step 4: Run complete verification**

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
git diff --check
git status --short --branch
```

Expected: analyze has no issues, all tests pass, web build succeeds, diff check is clean.

- [ ] **Step 5: Review and merge**

Use `requesting-code-review`, fix every confirmed finding with a failing test first, rerun the full verification, then use `finishing-a-development-branch` to merge the feature branch into local `master`. Do not push without explicit user instruction.

## Self-review result

- Spec coverage: versions, safe structured 409, durable de-duplication, per-entity retry stop, cloud/local choices, offline queue, repeat conflict, global/ledger/account entries, item-by-item UI and destructive confirmation are each mapped to a task.
- Scope control: invitation roles/member management and authoritative cloud stats remain explicitly deferred to their own plans; this plan produces a complete, independently usable conflict center.
- Placeholder scan: no TBD/TODO or undefined implementation step remains.
- Type consistency: all tasks use `ApiConflictPayload`, `ConflictRecord`, `ConflictStore`, `ConflictSnapshotCodec`, `ConflictCoordinator` and `ConflictResolutionGateway` consistently.
