import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/transaction_repository.dart';

void main() {
  group('RemoteTransactionRepository', () {
    test('loads all transaction pages for a ledger', () async {
      SharedPreferences.setMockInitialValues({});
      final apiClient = _FakeApiClient([
        {
          'page': 1,
          'pageSize': 2,
          'total': 3,
          'records': [_transactionJson('tx-1'), _transactionJson('tx-2')],
        },
        {
          'page': 2,
          'pageSize': 2,
          'total': 3,
          'records': [_transactionJson('tx-3')],
        },
      ]);
      final repository = RemoteTransactionRepository(
        apiClient: apiClient,
        database: DatabaseService(),
      );

      final transactions = await repository.getTransactionsForLedger(
        'ledger-1',
      );

      expect(transactions.map((transaction) => transaction.uuid), [
        'tx-1',
        'tx-2',
        'tx-3',
      ]);
      expect(transactions.first.payerPersonUuid, 'person-1');
      expect(apiClient.requestedPages, [1, 2]);
    });

    test('updates synced remote transaction after restart', () async {
      SharedPreferences.setMockInitialValues({});
      final apiClient = _FakeApiClient([]);
      final database = DatabaseService();
      final repository = RemoteTransactionRepository(
        apiClient: apiClient,
        database: database,
      );
      final transaction = _transaction()
        ..uuid = '1234567890abcdef1234567890abcdef'
        ..clientOperationId = 'client-op-1'
        ..version = 3
        ..amount = 18.5
        ..pendingSync = true;

      await database.saveTransaction(transaction);
      await repository.syncPendingTransactions('ledger-1');

      expect(apiClient.putPaths, [
        '/api/ledgers/ledger-1/transactions/1234567890abcdef1234567890abcdef',
      ]);
      expect(apiClient.postPaths, isEmpty);
    });

    test('deletes remote transaction locally before sync', () async {
      SharedPreferences.setMockInitialValues({});
      final apiClient = _FakeApiClient([]);
      final database = DatabaseService();
      final repository = RemoteTransactionRepository(
        apiClient: apiClient,
        database: database,
      );
      final transaction = _syncedTransaction();
      await database.saveTransaction(transaction);

      await repository.deleteTransaction('ledger-1', transaction.uuid);

      expect(await database.getTransactionsForLedger('ledger-1'), isEmpty);
      final deleted = await database.getTransactionsForLedger(
        'ledger-1',
        includeDeleted: true,
      );
      expect(deleted.single.isDeleted, isTrue);
      expect(deleted.single.pendingSync, isTrue);
      expect(apiClient.deletePaths, isEmpty);
    });

    test('syncs pending remote transaction deletion', () async {
      SharedPreferences.setMockInitialValues({});
      final apiClient = _FakeApiClient([]);
      final database = DatabaseService();
      final repository = RemoteTransactionRepository(
        apiClient: apiClient,
        database: database,
      );
      final transaction = _syncedTransaction()
        ..isDeleted = true
        ..pendingSync = true;
      await database.saveTransaction(transaction);

      await repository.syncPendingTransactions('ledger-1');

      expect(apiClient.deletePaths, [
        '/api/ledgers/ledger-1/transactions/1234567890abcdef1234567890abcdef',
      ]);
      final deleted = await database.getTransactionsForLedger(
        'ledger-1',
        includeDeleted: true,
      );
      expect(deleted.single.isDeleted, isTrue);
      expect(deleted.single.pendingSync, isFalse);
    });

    test(
      'uploads local transaction through mapped remote identities',
      () async {
        SharedPreferences.setMockInitialValues({});
        final apiClient = _MappedTransactionApiClient();
        final database = DatabaseService();
        final repository = RemoteTransactionRepository(
          apiClient: apiClient,
          database: database,
        );
        await database.saveLedger(
          Ledger()
            ..uuid = 'local-ledger'
            ..syncedRemoteUuid = _remoteLedgerUuid
            ..name = '离线账本'
            ..baseCurrencyCode = 'CNY',
        );
        await database.savePerson(
          Person()
            ..uuid = 'local-person'
            ..syncedRemoteUuid = _remotePersonUuid
            ..name = '本人',
        );
        await database.saveTransaction(
          _transaction()
            ..uuid = 'local-transaction'
            ..ledgerUuid = 'local-ledger'
            ..payerPersonUuid = 'local-person'
            ..personUuids = ['local-person']
            ..pendingSync = true,
        );

        await repository.syncPendingTransactions('local-ledger');

        expect(apiClient.postPaths, [
          '/api/ledgers/$_remoteLedgerUuid/transactions',
        ]);
        expect(apiClient.postedData?['payerPersonUuid'], _remotePersonUuid);
        expect(apiClient.postedData?['personUuids'], [_remotePersonUuid]);
        final cached = await database.getTransactionsForLedger('local-ledger');
        expect(cached.single.uuid, _remoteTransactionUuid);
        expect(cached.single.ledgerUuid, 'local-ledger');
        expect(cached.single.pendingSync, isFalse);
      },
    );
  });
}

TransactionRecord _transaction() {
  return TransactionRecord()
    ..uuid = 'local-tx-1'
    ..ledgerUuid = 'ledger-1'
    ..type = 0
    ..payerPersonUuid = 'person-1'
    ..clientOperationId = 'client-op-1'
    ..version = 1
    ..amount = 12.5
    ..currencyCode = 'CNY'
    ..category = '餐饮'
    ..note = ''
    ..personUuids = ['person-1']
    ..createdAt = DateTime(2026, 5, 22, 12);
}

TransactionRecord _syncedTransaction() {
  return _transaction()
    ..uuid = '1234567890abcdef1234567890abcdef'
    ..clientOperationId = 'client-op-1'
    ..version = 3
    ..pendingSync = false;
}

Map<String, Object?> _transactionJson(String uuid) {
  return {
    'uuid': uuid,
    'ledgerUuid': 'ledger-1',
    'type': 0,
    'payerPersonUuid': 'person-1',
    'amount': 12.5,
    'currencyCode': 'CNY',
    'category': '餐饮',
    'note': '',
    'personUuids': ['person-1'],
    'happenedAt': '2026-05-22T12:00:00',
    'version': 1,
  };
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this._pages) : super(tokenStore: TokenStore());

  final List<Map<String, Object?>> _pages;
  final List<int> requestedPages = [];
  final List<String> postPaths = [];
  final List<String> putPaths = [];
  final List<String> deletePaths = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    requestedPages.add(queryParameters?['page'] as int);
    return fromJson!(_pages.removeAt(0));
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    postPaths.add(path);
    return fromJson!(_transactionJson('posted-tx'));
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    putPaths.add(path);
    return fromJson!(_transactionJson(path.split('/').last));
  }

  @override
  Future<void> deleteVoid(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) async {
    deletePaths.add(path);
  }
}

const _remoteLedgerUuid = '0123456789abcdef0123456789abcdef';
const _remotePersonUuid = 'abcdef0123456789abcdef0123456789';
const _remoteTransactionUuid = 'fedcba9876543210fedcba9876543210';

class _MappedTransactionApiClient extends ApiClient {
  _MappedTransactionApiClient() : super(tokenStore: TokenStore());

  final List<String> postPaths = [];
  Map<String, dynamic>? postedData;

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    postPaths.add(path);
    postedData = data! as Map<String, dynamic>;
    return fromJson!({
      'uuid': _remoteTransactionUuid,
      'ledgerUuid': _remoteLedgerUuid,
      'type': 0,
      'payerPersonUuid': _remotePersonUuid,
      'amount': 12.5,
      'currencyCode': 'CNY',
      'category': '餐饮',
      'note': '',
      'personUuids': [_remotePersonUuid],
      'happenedAt': '2026-05-22T12:00:00',
      'version': 1,
    });
  }
}
