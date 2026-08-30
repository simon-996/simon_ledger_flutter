import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/repositories/ledger_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/person_repository.dart';
import 'package:simon_ledger_flutter/core/services/conflict_coordinator.dart';
import 'package:simon_ledger_flutter/core/services/conflict_snapshot_codec.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';

const _ledgerUuid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _personUuid = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ledger update conflict is removed from automatic retry', () async {
    final database = DatabaseService();
    final store = ConflictStore();
    final codec = ConflictSnapshotCodec(
      database: database,
      profileStore: const LocalProfileStore(),
    );
    final api = _ConflictApiClient(_ledgerConflict());
    final repository = RemoteLedgerRepository(
      apiClient: api,
      database: database,
      conflictCoordinator: _coordinator(store, codec),
      conflictCodec: codec,
    );
    await database.saveLedger(
      Ledger()
        ..uuid = _ledgerUuid
        ..name = '本机账本'
        ..baseCurrencyCode = 'CNY'
        ..exchangeRateToCNY = 1
        ..version = 2
        ..cloudPolicy = LedgerCloudPolicy.cloudManaged
        ..pendingSync = true,
    );

    await repository.syncPendingWrites(ledgerUuid: _ledgerUuid);

    expect(api.putData, containsPair('version', 2));
    final ledger = (await database.getAllLedgers()).single;
    expect(ledger.pendingSync, isFalse);
    expect(ledger.syncError, isNull);
    final conflict = (await store.readAll()).single;
    expect(conflict.entityType, ConflictEntityType.ledger);
    expect(conflict.localSnapshot['name'], '本机账本');
  });

  test('person update conflict is removed from automatic retry', () async {
    final database = DatabaseService();
    final store = ConflictStore();
    final codec = ConflictSnapshotCodec(
      database: database,
      profileStore: const LocalProfileStore(),
    );
    final api = _ConflictApiClient(_personConflict());
    await database.saveLedger(
      Ledger()
        ..uuid = _ledgerUuid
        ..name = '共享账本'
        ..baseCurrencyCode = 'CNY'
        ..cloudPolicy = LedgerCloudPolicy.cloudManaged,
    );
    await database.savePerson(
      Person()
        ..uuid = _personUuid
        ..name = '本机参与人'
        ..avatar = '🐱'
        ..version = 2
        ..pendingSync = true
        ..pendingLedgerUuid = _ledgerUuid,
    );
    final repository = RemotePersonRepository(
      apiClient: api,
      ledgerRepository: LocalLedgerRepository(database),
      database: database,
      conflictCoordinator: _coordinator(store, codec),
      conflictCodec: codec,
    );

    await repository.syncPendingPeople(_ledgerUuid);

    expect(api.putData, containsPair('version', 2));
    final person = (await database.getAllPeople()).single;
    expect(person.pendingSync, isFalse);
    expect(person.pendingLedgerUuid, isNull);
    expect(person.syncError, isNull);
    final conflict = (await store.readAll()).single;
    expect(conflict.entityType, ConflictEntityType.person);
    expect(conflict.localSnapshot['name'], '本机参与人');
  });
}

ConflictCoordinator _coordinator(
  ConflictStore store,
  ConflictSnapshotCodec codec,
) {
  return ConflictCoordinator(
    store: store,
    codec: codec,
    gateway: _UnusedGateway(),
  );
}

ApiException _ledgerConflict() {
  return const ApiException(
    code: 409001,
    statusCode: 409,
    message: '账本已被修改',
    conflict: ApiConflictPayload(
      entityType: ConflictEntityType.ledger,
      entityUuid: _ledgerUuid,
      submittedVersion: 2,
      remoteVersion: 3,
      remoteDeleted: false,
      remoteSnapshot: {
        'uuid': _ledgerUuid,
        'name': '云端账本',
        'baseCurrencyCode': 'CNY',
        'exchangeRateToCny': 1.0,
        'version': 3,
      },
    ),
  );
}

ApiException _personConflict() {
  return const ApiException(
    code: 409001,
    statusCode: 409,
    message: '参与人已被修改',
    conflict: ApiConflictPayload(
      entityType: ConflictEntityType.person,
      entityUuid: _personUuid,
      submittedVersion: 2,
      remoteVersion: 3,
      remoteDeleted: false,
      remoteSnapshot: {
        'uuid': _personUuid,
        'ledgerUuid': _ledgerUuid,
        'name': '云端参与人',
        'avatar': '🐶',
        'version': 3,
      },
    ),
  );
}

class _ConflictApiClient extends ApiClient {
  _ConflictApiClient(this.error) : super(tokenStore: TokenStore());

  final ApiException error;
  Map<String, Object?>? putData;

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    putData = (data! as Map).cast<String, Object?>();
    throw error;
  }
}

class _UnusedGateway implements ConflictResolutionGateway {
  @override
  Future<ConflictMutationResult> submit(ConflictRecord record) {
    throw UnimplementedError();
  }
}
