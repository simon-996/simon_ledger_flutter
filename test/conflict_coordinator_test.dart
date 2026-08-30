import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/services/conflict_coordinator.dart';
import 'package:simon_ledger_flutter/core/services/conflict_snapshot_codec.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';
import 'package:simon_ledger_flutter/core/services/sync_identity_resolver.dart';

void main() {
  late DatabaseService database;
  late LocalProfileStore profileStore;
  late ConflictStore store;
  late ConflictSnapshotCodec codec;
  late _FakeGateway gateway;
  late ConflictCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = DatabaseService();
    profileStore = const LocalProfileStore();
    store = ConflictStore();
    codec = ConflictSnapshotCodec(
      database: database,
      profileStore: profileStore,
    );
    gateway = _FakeGateway();
    coordinator = ConflictCoordinator(
      store: store,
      codec: codec,
      gateway: gateway,
    );
  });

  test('capture persists only a structured optimistic conflict', () async {
    final captured = await coordinator.capture(
      error: _conflictError(remoteVersion: 4),
      operation: ConflictOperation.update,
      ledgerUuid: 'ledger-local',
      localUuid: 'transaction-local',
      localSnapshot: const {'amount': 20.0, 'version': 2},
    );
    final ignored = await coordinator.capture(
      error: const ApiException(
        code: 409001,
        statusCode: 409,
        message: '缺少结构化数据',
      ),
      operation: ConflictOperation.update,
      ledgerUuid: 'ledger-local',
      localUuid: 'transaction-other',
      localSnapshot: const {'amount': 10.0, 'version': 1},
    );

    expect(captured, isTrue);
    expect(ignored, isFalse);
    final record = (await store.readAll()).single;
    expect(record.entityType, ConflictEntityType.transaction);
    expect(record.remoteUuid, 'transaction-remote');
    expect(record.localUuid, 'transaction-local');
    expect(record.baseVersion, 2);
    expect(record.remoteVersion, 4);
    expect(record.remoteSnapshot['amount'], 28.5);
    expect(record.state, ConflictState.unresolved);
  });

  test(
    'use remote applies the snapshot locally and removes the conflict',
    () async {
      await profileStore.save(
        const LocalProfile(
          nickname: '本机昵称',
          avatarIcon: 'star',
          pendingSync: true,
          remoteVersion: 2,
        ),
      );
      await coordinator.capture(
        error: _conflictError(
          entityType: ConflictEntityType.profile,
          entityUuid: 'user-1',
          remoteVersion: 4,
          remoteSnapshot: const {
            'uuid': 'user-1',
            'nickname': '云端昵称',
            'avatar': '🐶',
            'version': 4,
          },
        ),
        operation: ConflictOperation.update,
        localUuid: 'user-1',
        localSnapshot: const {
          'uuid': 'user-1',
          'nickname': '本机昵称',
          'avatar': '⭐',
          'version': 2,
        },
      );

      await coordinator.useRemote((await store.readAll()).single.id);

      final profile = await profileStore.read();
      expect(profile.nickname, '云端昵称');
      expect(profile.avatarIcon, 'avatar_02');
      expect(profile.remoteVersion, 4);
      expect(profile.pendingSync, isFalse);
      expect(await store.readAll(), isEmpty);
    },
  );

  test('keep local applies the returned server version and resolves', () async {
    await profileStore.save(
      const LocalProfile(
        nickname: '本机昵称',
        avatarIcon: 'star',
        remoteVersion: 2,
      ),
    );
    await _captureProfile(coordinator, remoteVersion: 4);
    gateway.nextResult = const ConflictMutationResult(
      version: 5,
      deleted: false,
      snapshot: {
        'uuid': 'user-1',
        'nickname': '本机昵称',
        'avatar': '⭐',
        'version': 5,
      },
    );

    final outcome = await coordinator.keepLocal(
      (await store.readAll()).single.id,
    );

    expect(outcome, ConflictResolutionOutcome.resolved);
    expect(gateway.submitted, hasLength(1));
    expect(gateway.submitted.single.remoteVersion, 4);
    expect((await profileStore.read()).remoteVersion, 5);
    expect(await store.readAll(), isEmpty);
  });

  test('network failure queues local choice and retries it later', () async {
    await profileStore.save(
      const LocalProfile(nickname: '本机昵称', avatarIcon: 'star'),
    );
    await _captureProfile(coordinator, remoteVersion: 2);
    gateway.nextError = const ApiException(code: -1, message: '网络不可用');

    final first = await coordinator.keepLocal(
      (await store.readAll()).single.id,
    );
    final queued = (await store.readAll()).single;
    expect(first, ConflictResolutionOutcome.queued);
    expect(queued.state, ConflictState.queuedLocal);
    expect(queued.error, contains('联网'));

    gateway
      ..nextError = null
      ..nextResult = const ConflictMutationResult(
        version: 3,
        deleted: false,
        snapshot: {
          'uuid': 'user-1',
          'nickname': '本机昵称',
          'avatar': '⭐',
          'version': 3,
        },
      );
    await coordinator.retryQueuedLocal();

    expect(gateway.submitted, hasLength(2));
    expect(await store.readAll(), isEmpty);
    expect((await profileStore.read()).remoteVersion, 3);
  });

  test(
    'second conflict refreshes the same record for explicit review',
    () async {
      await _captureProfile(coordinator, remoteVersion: 2);
      final original = (await store.readAll()).single;
      gateway.nextError = _conflictError(
        entityType: ConflictEntityType.profile,
        entityUuid: 'user-1',
        submittedVersion: 2,
        remoteVersion: 3,
        remoteSnapshot: const {
          'uuid': 'user-1',
          'nickname': '另一台设备',
          'avatar': '🐱',
          'version': 3,
        },
      );

      final outcome = await coordinator.keepLocal(original.id);

      expect(outcome, ConflictResolutionOutcome.requiresReview);
      final refreshed = (await store.readAll()).single;
      expect(refreshed.id, original.id);
      expect(refreshed.remoteVersion, 3);
      expect(refreshed.remoteSnapshot['nickname'], '另一台设备');
      expect(refreshed.state, ConflictState.unresolved);
      expect(refreshed.error, isNull);
    },
  );

  test('permission and validation failures remain visible as failed', () async {
    await _captureProfile(coordinator, remoteVersion: 2);
    gateway.nextError = const ApiException(
      code: 403001,
      statusCode: 403,
      message: '你没有权限执行此操作',
    );

    final outcome = await coordinator.keepLocal(
      (await store.readAll()).single.id,
    );

    expect(outcome, ConflictResolutionOutcome.failed);
    final failed = (await store.readAll()).single;
    expect(failed.state, ConflictState.failed);
    expect(failed.error, '你没有权限执行此操作');
  });

  test(
    'keeping a local delete already deleted remotely resolves without API',
    () async {
      await database.savePerson(
        Person()
          ..uuid = 'person-local'
          ..name = '本机参与人'
          ..isDeleted = true
          ..version = 2,
      );
      await coordinator.capture(
        error: _conflictError(
          entityType: ConflictEntityType.person,
          entityUuid: 'person-remote',
          remoteVersion: 4,
          remoteDeleted: true,
          remoteSnapshot: const {
            'uuid': 'person-remote',
            'name': '云端参与人',
            'avatar': '🐶',
            'version': 4,
          },
        ),
        operation: ConflictOperation.delete,
        ledgerUuid: 'ledger-local',
        localUuid: 'person-local',
        localSnapshot: const {'name': '本机参与人', 'version': 2},
      );

      final outcome = await coordinator.keepLocal(
        (await store.readAll()).single.id,
      );

      expect(outcome, ConflictResolutionOutcome.resolved);
      expect(gateway.submitted, isEmpty);
      expect(await store.readAll(), isEmpty);
      final saved = (await database.getAllPeople(includeDeleted: true)).single;
      expect(saved.isDeleted, isTrue);
      expect(saved.version, 4);
    },
  );

  test(
    'API gateway maps local transaction identities and update route',
    () async {
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-local'
          ..syncedRemoteUuid = 'ledger-remote'
          ..name = '账本'
          ..baseCurrencyCode = 'CNY',
      );
      await database.savePerson(
        Person()
          ..uuid = 'person-local-1'
          ..syncedRemoteUuid = 'person-remote-1'
          ..name = '甲',
      );
      await database.savePerson(
        Person()
          ..uuid = 'person-local-2'
          ..syncedRemoteUuid = 'person-remote-2'
          ..name = '乙',
      );
      final api = _RecordingApiClient()
        ..response = {
          'uuid': 'transaction-remote',
          'version': 5,
          'deleted': false,
        };
      final apiGateway = ApiConflictResolutionGateway(
        apiClient: api,
        codec: codec,
        identityResolver: SyncIdentityResolver(database),
      );

      final result = await apiGateway.submit(
        _record(
          entityType: ConflictEntityType.transaction,
          ledgerUuid: 'ledger-local',
          localUuid: 'transaction-remote',
          remoteUuid: 'transaction-remote',
          remoteVersion: 4,
          localSnapshot: const {
            'type': 0,
            'payerPersonUuid': 'person-local-1',
            'amount': 88.5,
            'currencyCode': 'CNY',
            'category': '餐饮',
            'note': '晚餐',
            'happenedAt': '2026-08-26T19:30:00.000',
            'personUuids': ['person-local-1', 'person-local-2'],
          },
        ),
      );

      expect(api.method, 'PUT');
      expect(
        api.path,
        '/api/ledgers/ledger-remote/transactions/transaction-remote',
      );
      expect(api.data, containsPair('payerPersonUuid', 'person-remote-1'));
      expect((api.data! as Map<String, Object?>)['personUuids'], [
        'person-remote-1',
        'person-remote-2',
      ]);
      expect(api.data, containsPair('version', 4));
      expect(api.idempotencyKey, contains('conflict-1'));
      expect(result.version, 5);
    },
  );

  test(
    'API gateway sends complete restore data and version-only delete',
    () async {
      final api = _RecordingApiClient()
        ..response = {
          'uuid': 'ledger-remote',
          'name': '恢复名称',
          'baseCurrencyCode': 'CNY',
          'exchangeRateToCny': 1.0,
          'version': 6,
        };
      final apiGateway = ApiConflictResolutionGateway(
        apiClient: api,
        codec: codec,
        identityResolver: SyncIdentityResolver(database),
      );
      await apiGateway.submit(
        _record(
          entityType: ConflictEntityType.ledger,
          ledgerUuid: 'ledger-remote',
          localUuid: 'ledger-remote',
          remoteUuid: 'ledger-remote',
          operation: ConflictOperation.restore,
          remoteVersion: 5,
          localSnapshot: const {
            'name': '恢复名称',
            'baseCurrencyCode': 'CNY',
            'exchangeRateToCny': 1.0,
          },
        ),
      );

      expect(api.method, 'POST');
      expect(api.path, '/api/ledgers/ledger-remote/restore');
      expect(api.data, {
        'name': '恢复名称',
        'baseCurrencyCode': 'CNY',
        'exchangeRateToCny': 1.0,
        'version': 5,
      });

      api.response = {'uuid': 'member-1', 'version': 8, 'deleted': true};
      await apiGateway.submit(
        _record(
          entityType: ConflictEntityType.member,
          ledgerUuid: 'ledger-remote',
          localUuid: 'member-1',
          remoteUuid: 'member-1',
          operation: ConflictOperation.delete,
          remoteVersion: 7,
          localSnapshot: const {'role': 'editor'},
        ),
      );

      expect(api.method, 'DELETE');
      expect(api.path, '/api/ledgers/ledger-remote/members/member-1');
      expect(api.data, {'version': 7});
    },
  );

  test(
    'API gateway restores a locally kept record when remote is deleted',
    () async {
      final api = _RecordingApiClient()
        ..response = {
          'uuid': 'ledger-remote',
          'name': '本机名称',
          'baseCurrencyCode': 'CNY',
          'exchangeRateToCny': 1.0,
          'version': 5,
          'deleted': false,
        };
      final apiGateway = ApiConflictResolutionGateway(
        apiClient: api,
        codec: codec,
        identityResolver: SyncIdentityResolver(database),
      );

      await apiGateway.submit(
        _record(
          entityType: ConflictEntityType.ledger,
          ledgerUuid: 'ledger-remote',
          localUuid: 'ledger-remote',
          remoteUuid: 'ledger-remote',
          operation: ConflictOperation.update,
          remoteVersion: 4,
          remoteDeleted: true,
          localSnapshot: const {
            'name': '本机名称',
            'baseCurrencyCode': 'CNY',
            'exchangeRateToCny': 1.0,
          },
        ),
      );

      expect(api.method, 'POST');
      expect(api.path, '/api/ledgers/ledger-remote/restore');
      expect(api.data, containsPair('version', 4));
      expect(api.idempotencyKey, contains('restore'));
    },
  );
}

Future<void> _captureProfile(
  ConflictCoordinator coordinator, {
  required int remoteVersion,
}) {
  return coordinator
      .capture(
        error: _conflictError(
          entityType: ConflictEntityType.profile,
          entityUuid: 'user-1',
          submittedVersion: 1,
          remoteVersion: remoteVersion,
          remoteSnapshot: {
            'uuid': 'user-1',
            'nickname': '云端昵称',
            'avatar': '🐶',
            'version': remoteVersion,
          },
        ),
        operation: ConflictOperation.update,
        localUuid: 'user-1',
        localSnapshot: const {
          'uuid': 'user-1',
          'nickname': '本机昵称',
          'avatar': '⭐',
          'version': 1,
        },
      )
      .then((_) {});
}

ApiException _conflictError({
  ConflictEntityType entityType = ConflictEntityType.transaction,
  String entityUuid = 'transaction-remote',
  int submittedVersion = 2,
  int remoteVersion = 3,
  bool remoteDeleted = false,
  Map<String, Object?> remoteSnapshot = const {
    'uuid': 'transaction-remote',
    'amount': 28.5,
    'version': 3,
  },
}) {
  return ApiException(
    code: 409001,
    statusCode: 409,
    message: '数据已被其他设备修改',
    conflict: ApiConflictPayload(
      entityType: entityType,
      entityUuid: entityUuid,
      submittedVersion: submittedVersion,
      remoteVersion: remoteVersion,
      remoteDeleted: remoteDeleted,
      remoteSnapshot: remoteSnapshot,
    ),
  );
}

ConflictRecord _record({
  required ConflictEntityType entityType,
  required String? ledgerUuid,
  required String localUuid,
  required String remoteUuid,
  ConflictOperation operation = ConflictOperation.update,
  bool remoteDeleted = false,
  required int remoteVersion,
  required Map<String, Object?> localSnapshot,
}) {
  return ConflictRecord(
    id: 'conflict-1',
    entityType: entityType,
    ledgerUuid: ledgerUuid,
    localUuid: localUuid,
    remoteUuid: remoteUuid,
    operation: operation,
    baseVersion: 1,
    remoteVersion: remoteVersion,
    localSnapshot: localSnapshot,
    remoteSnapshot: const {},
    remoteDeleted: remoteDeleted,
    detectedAt: DateTime(2026, 8, 26),
  );
}

class _FakeGateway implements ConflictResolutionGateway {
  ConflictMutationResult nextResult = const ConflictMutationResult(
    version: 2,
    deleted: false,
  );
  Object? nextError;
  final submitted = <ConflictRecord>[];

  @override
  Future<ConflictMutationResult> submit(ConflictRecord record) async {
    submitted.add(record);
    final error = nextError;
    if (error != null) throw error;
    return nextResult;
  }
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(tokenStore: TokenStore());

  String? method;
  String? path;
  Object? data;
  String? idempotencyKey;
  Map<String, Object?> response = const {};

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    _record('PUT', path, data, idempotencyKey);
    return fromJson!(response);
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    _record('POST', path, data, idempotencyKey);
    return fromJson!(response);
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    _record('DELETE', path, data, idempotencyKey);
    return fromJson!(response);
  }

  void _record(String method, String path, Object? data, String? key) {
    this.method = method;
    this.path = path;
    this.data = data;
    idempotencyKey = key;
  }
}
