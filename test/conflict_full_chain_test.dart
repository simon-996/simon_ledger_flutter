import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/repositories/ledger_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/person_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/transaction_repository.dart';
import 'package:simon_ledger_flutter/core/services/conflict_coordinator.dart';
import 'package:simon_ledger_flutter/core/services/conflict_snapshot_codec.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';
import 'package:simon_ledger_flutter/core/services/sync_coordinator.dart';

const _ledgerUuid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _personUuid = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _transactionUuid = 'cccccccccccccccccccccccccccccccc';

void main() {
  test(
    'one entity conflict does not block another and remote can apply offline after restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      final ledger = Ledger()
        ..uuid = _ledgerUuid
        ..name = '家庭账本'
        ..baseCurrencyCode = 'CNY'
        ..cloudPolicy = LedgerCloudPolicy.cloudManaged
        ..personUuids = [_personUuid];
      final person = Person()
        ..uuid = _personUuid
        ..name = '本机参与人'
        ..avatar = '🐱'
        ..version = 2
        ..pendingSync = true
        ..pendingLedgerUuid = _ledgerUuid;
      final transaction = TransactionRecord()
        ..uuid = _transactionUuid
        ..ledgerUuid = _ledgerUuid
        ..type = 0
        ..amount = 20
        ..currencyCode = 'CNY'
        ..category = '餐饮'
        ..note = '本机早餐'
        ..personUuids = [_personUuid]
        ..createdAt = DateTime.utc(2026, 8, 30, 8)
        ..version = 2
        ..pendingSync = true;
      await database.saveLedger(ledger);
      await database.savePerson(person);
      await database.saveTransaction(transaction);

      final store = ConflictStore();
      final codec = ConflictSnapshotCodec(
        database: database,
        profileStore: const LocalProfileStore(),
      );
      final conflictCoordinator = ConflictCoordinator(
        store: store,
        codec: codec,
        gateway: _OfflineGateway(),
      );
      final api = _PersonConflictTransactionSuccessApiClient();
      final personRepository = RemotePersonRepository(
        apiClient: api,
        ledgerRepository: LocalLedgerRepository(database),
        database: database,
        conflictCoordinator: conflictCoordinator,
        conflictCodec: codec,
      );
      final transactionRepository = RemoteTransactionRepository(
        apiClient: api,
        database: database,
        conflictCoordinator: conflictCoordinator,
        conflictCodec: codec,
      );
      final syncCoordinator = SyncCoordinator(
        ledgerRepository: LocalLedgerRepository(database),
        personRepository: personRepository,
        transactionRepository: transactionRepository,
        database: database,
        conflictCoordinator: conflictCoordinator,
      );

      final result = await syncCoordinator.syncLedger(_ledgerUuid, force: true);

      expect(result.error, isNull);
      expect(result.synced, 1);
      expect(api.personUpdateCount, 1);
      expect(api.transactionUpdateCount, 1);
      final persistedConflict = (await ConflictStore().readAll()).single;
      expect(persistedConflict.entityType, ConflictEntityType.person);
      expect(persistedConflict.remoteSnapshot['name'], '云端参与人');
      final syncedTransaction = (await database.getTransactionsForLedger(
        _ledgerUuid,
      )).single;
      expect(syncedTransaction.pendingSync, isFalse);
      expect(syncedTransaction.version, 3);
      expect(syncedTransaction.note, '云端确认');

      final reopenedStore = ConflictStore();
      final restartedCoordinator = ConflictCoordinator(
        store: reopenedStore,
        codec: codec,
        gateway: _OfflineGateway(),
      );
      await restartedCoordinator.useRemote(persistedConflict.id);

      expect(await ConflictStore().readAll(), isEmpty);
      final appliedPerson = (await database.getAllPeople()).single;
      expect(appliedPerson.name, '云端参与人');
      expect(appliedPerson.avatar, '🐶');
      expect(appliedPerson.version, 3);
      expect(appliedPerson.pendingSync, isFalse);
      final transactionAfterResolution =
          (await database.getTransactionsForLedger(_ledgerUuid)).single;
      expect(transactionAfterResolution.note, '云端确认');
      expect(transactionAfterResolution.version, 3);
    },
  );
}

class _PersonConflictTransactionSuccessApiClient extends ApiClient {
  _PersonConflictTransactionSuccessApiClient()
    : super(tokenStore: TokenStore());

  int personUpdateCount = 0;
  int transactionUpdateCount = 0;

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    if (path.contains('/people/')) {
      personUpdateCount += 1;
      throw const ApiException(
        code: 409001,
        statusCode: 409,
        message: '参与人已在其他设备修改',
        conflict: ApiConflictPayload(
          entityType: ConflictEntityType.person,
          entityUuid: _personUuid,
          submittedVersion: 2,
          remoteVersion: 3,
          remoteDeleted: false,
          remoteSnapshot: {
            'uuid': _personUuid,
            'name': '云端参与人',
            'avatar': '🐶',
            'linkedUserUuid': null,
            'version': 3,
          },
        ),
      );
    }
    transactionUpdateCount += 1;
    return fromJson!({
      'uuid': _transactionUuid,
      'ledgerUuid': _ledgerUuid,
      'type': 0,
      'amount': 20.0,
      'currencyCode': 'CNY',
      'category': '餐饮',
      'note': '云端确认',
      'personUuids': [_personUuid],
      'happenedAt': '2026-08-30T08:00:00.000Z',
      'clientOperationId': _transactionUuid,
      'version': 3,
    });
  }
}

class _OfflineGateway implements ConflictResolutionGateway {
  @override
  Future<ConflictMutationResult> submit(ConflictRecord record) {
    throw const ApiException(code: -1, message: 'offline');
  }
}
