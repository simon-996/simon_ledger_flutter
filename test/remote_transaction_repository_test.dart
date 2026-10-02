import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/money.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/repositories/transaction_repository.dart';
import 'package:simon_ledger_flutter/core/services/conflict_coordinator.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_queue.dart';
import 'package:simon_ledger_flutter/core/services/conflict_snapshot_codec.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_detail_sheet.dart';

void main() {
  group('RemoteTransactionRepository', () {
    test(
      'creates a confirmed AI draft before updating its server uuid',
      () async {
        SharedPreferences.setMockInitialValues({});
        final database = DatabaseService();
        final queue = AiDraftQueue(
          scope: const LocalDataScope.account('alice'),
          loadTransactions: database.getTransactionsForLedger,
        );
        final item = (await queue.add('ledger-1', [
          AiDraft(
            sourceText: '晚饭20泰铢',
            type: 0,
            amount: 20,
            currencyCode: 'THB',
            personUuids: const ['person-1'],
            unresolvedNames: const [],
          ),
        ])).single;
        final api = _UndoApiClient()..release.complete();
        final repository = RemoteTransactionRepository(
          apiClient: api,
          database: database,
        );

        await repository.saveTransaction(
          _transaction()
            ..uuid = item.uuid
            ..clientOperationId = item.operationId
            ..amount = 20
            ..currencyCode = 'THB',
        );
        final created = await repository.syncPendingTransactions('ledger-1');

        expect(created.error, isNull);
        expect(api.postPaths, ['/api/ledgers/ledger-1/transactions']);
        expect(api.postKeys, [item.operationId]);
        expect(api.putPaths, isEmpty);
        final saved = (await database.getTransactionsForLedger(
          'ledger-1',
        )).single;
        expect(saved.uuid, _remoteTransactionUuid);
        expect(saved.clientOperationId, item.operationId);
        expect(saved.pendingSync, isFalse);
        expect(await queue.load('ledger-1'), isEmpty);

        await repository.saveTransaction(saved..amount = 25);
        await repository.syncPendingTransactions('ledger-1');
        expect(api.postPaths, hasLength(1));
        expect(api.putPaths, [
          '/api/ledgers/ledger-1/transactions/$_remoteTransactionUuid',
        ]);
        expect(api.putData?['amount'], 25);
      },
    );

    test(
      'retries a persisted AI create using its original operation id',
      () async {
        SharedPreferences.setMockInitialValues({});
        final database = DatabaseService();
        const operationId = 'd8053d040ae3995076308cc17f9cb0e0';
        await database.saveTransaction(
          _transaction()
            ..uuid = operationId
            ..clientOperationId = operationId
            ..pendingSync = true
            ..syncError = '流水不存在',
        );
        final api = _UndoApiClient()..release.complete();
        final repository = RemoteTransactionRepository(
          apiClient: api,
          database: database,
        );

        final result = await repository.syncPendingTransactions('ledger-1');

        expect(result.error, isNull);
        expect(api.postPaths, ['/api/ledgers/ledger-1/transactions']);
        expect(api.postKeys, [operationId]);
        expect(api.putPaths, isEmpty);
        final saved = (await database.getTransactionsForLedger(
          'ledger-1',
        )).single;
        expect(saved.uuid, _remoteTransactionUuid);
        expect(saved.pendingSync, isFalse);
        expect(saved.syncError, isNull);
      },
    );

    test(
      'undo of a pending AI create deletes the returned server uuid',
      () async {
        SharedPreferences.setMockInitialValues({});
        final database = DatabaseService();
        const operationId = 'd8053d040ae3995076308cc17f9cb0e0';
        await database.saveTransaction(
          _transaction()
            ..uuid = operationId
            ..clientOperationId = operationId
            ..pendingSync = true,
        );
        final api = _UndoApiClient()..release.complete();
        final repository = RemoteTransactionRepository(
          apiClient: api,
          database: database,
        );

        await repository.deleteTransaction('ledger-1', operationId);
        final result = await repository.syncPendingTransactions('ledger-1');

        expect(result.error, isNull);
        expect(api.postKeys, [operationId]);
        expect(api.putPaths, isEmpty);
        expect(api.deletePaths, [
          '/api/ledgers/ledger-1/transactions/$_remoteTransactionUuid',
        ]);
        expect(await database.getTransactionsForLedger('ledger-1'), isEmpty);
        expect(
          (await database.getTransactionsForLedger(
            'ledger-1',
            includeDeleted: true,
          )).where((record) => record.pendingSync),
          isEmpty,
        );
      },
    );

    test(
      'editing a remote row without an operation id still uses PUT',
      () async {
        SharedPreferences.setMockInitialValues({});
        final database = DatabaseService();
        final api = _UndoApiClient()..release.complete();
        final repository = RemoteTransactionRepository(
          apiClient: api,
          database: database,
        );
        await repository.saveTransaction(
          _syncedTransaction()..clientOperationId = null,
        );
        await repository.syncPendingTransactions('ledger-1');

        expect(api.postPaths, isEmpty);
        expect(api.putPaths, [
          '/api/ledgers/ledger-1/transactions/1234567890abcdef1234567890abcdef',
        ]);
      },
    );

    test(
      'failed AI undo retries deletion only for the server identity',
      () async {
        SharedPreferences.setMockInitialValues({});
        final database = DatabaseService();
        const operationId = 'd8053d040ae3995076308cc17f9cb0e0';
        await database.saveTransaction(
          _transaction()
            ..uuid = operationId
            ..clientOperationId = operationId
            ..isDeleted = true
            ..pendingSync = true,
        );
        final api = _UndoApiClient()
          ..failDeletion = true
          ..release.complete();
        final repository = RemoteTransactionRepository(
          apiClient: api,
          database: database,
        );

        final failed = await repository.syncPendingTransactions('ledger-1');
        expect(failed.error, isNotNull);
        final pending = (await database.getTransactionsForLedger(
          'ledger-1',
          includeDeleted: true,
        )).where((record) => record.pendingSync);
        expect(pending.map((record) => record.uuid), [_remoteTransactionUuid]);

        api.failDeletion = false;
        final retried = await repository.syncPendingTransactions('ledger-1');
        expect(retried.error, isNull);
        expect(api.postKeys, [operationId]);
        expect(api.deletePaths, [
          '/api/ledgers/ledger-1/transactions/$_remoteTransactionUuid',
        ]);
        expect(await database.getTransactionsForLedger('ledger-1'), isEmpty);
      },
    );

    testWidgets('shows a deleted creator on a retained remote transaction', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      final repository = RemoteTransactionRepository(
        apiClient: _FakeApiClient([
          {
            'page': 1,
            'pageSize': 100,
            'total': 1,
            'records': [
              {
                ..._transactionJson('retained-tx'),
                'createdByUserUuid': null,
                'createdByNickname': '旧昵称',
                'createdByAvatar': '😎',
              },
            ],
          },
        ]),
        database: database,
      );

      final transaction = (await repository.getTransactionsForLedger(
        'ledger-1',
      )).single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTransactionTile(
              category: transaction.category,
              date: '05-22 12:00',
              people: '',
              amount: formatTransactionPrimaryAmount(transaction),
              isExpense: transaction.type == 0,
              createdByText: transaction.createdByNickname,
              createdByAvatar: transaction.createdByAvatar,
            ),
          ),
        ),
      );

      expect(transaction.createdByUserUuid, isNull);
      expect(transaction.amount, 12.5);
      expect(find.text('- CNY 12.50'), findsOneWidget);
      expect(find.text('由 已注销用户 添加'), findsOneWidget);
      expect(find.text('由 旧昵称 添加'), findsNothing);
      expect(find.text('😎'), findsNothing);

      final cached = (await database.getTransactionsForLedger(
        'ledger-1',
      )).single;
      expect(cached.amount, 12.5);
      expect(cached.createdByNickname, '已注销用户');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TransactionDetailSheet(
                transaction: cached,
                peoplePool: const [],
                ledger: Ledger()
                  ..uuid = 'ledger-1'
                  ..name = '共享账本'
                  ..baseCurrencyCode = 'CNY',
              ),
            ),
          ),
        ),
      );
      expect(find.text('添加人'), findsOneWidget);
      expect(find.text('已注销用户'), findsOneWidget);
      expect(find.text('CNY 12.50'), findsWidgets);
    });

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
      expect(transactions.first.createdByNickname, isNull);
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

    test(
      'undo resolves a local alias after upload has replaced its uuid',
      () async {
        SharedPreferences.setMockInitialValues({});
        final api = _UndoApiClient()..release.complete();
        final db = DatabaseService();
        final repo = RemoteTransactionRepository(apiClient: api, database: db);
        final record = _transaction()..pendingSync = true;
        await db.saveTransaction(record);
        await repo.syncPendingTransactions('ledger-1');
        expect(
          (await db.getTransactionsForLedger('ledger-1')).single.uuid,
          _remoteTransactionUuid,
        );
        await repo.deleteTransaction('ledger-1', record.uuid);
        expect(await db.getTransactionsForLedger('ledger-1'), isEmpty);
        await repo.syncPendingTransactions('ledger-1');
        expect(api.deletePaths, [
          '/api/ledgers/ledger-1/transactions/$_remoteTransactionUuid',
        ]);
      },
    );

    test(
      'undo during upload stays deleted and deletes the returned remote row',
      () async {
        SharedPreferences.setMockInitialValues({});
        final api = _UndoApiClient();
        final db = DatabaseService();
        final repo = RemoteTransactionRepository(apiClient: api, database: db);
        final record = _transaction()..pendingSync = true;
        await db.saveTransaction(record);
        final upload = repo.syncPendingTransactions('ledger-1');
        await api.started.future;
        final secondSync = repo.syncPendingTransactions('ledger-1');
        await repo.deleteTransaction('ledger-1', record.uuid);
        expect(await db.getTransactionsForLedger('ledger-1'), isEmpty);
        api.release.complete();
        await Future.wait([upload, secondSync]);
        expect(await db.getTransactionsForLedger('ledger-1'), isEmpty);
        expect(api.postPaths, hasLength(1));
        expect(api.deletePaths, [
          '/api/ledgers/ledger-1/transactions/$_remoteTransactionUuid',
        ]);
      },
    );

    test('failed undo sync remains hidden during remote refresh', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _UndoApiClient()..release.complete();
      final db = DatabaseService();
      final repo = RemoteTransactionRepository(apiClient: api, database: db);
      final record = _transaction()..pendingSync = true;
      await db.saveTransaction(record);
      await repo.syncPendingTransactions('ledger-1');
      api.failDeletion = true;
      await repo.deleteTransaction('ledger-1', record.uuid);
      final refreshed = await repo.getTransactionsForLedger('ledger-1');
      expect(refreshed, isEmpty);
      expect(await db.getTransactionsForLedger('ledger-1'), isEmpty);
      final pending = (await db.getTransactionsForLedger(
        'ledger-1',
        includeDeleted: true,
      )).where((record) => record.pendingSync);
      expect(pending.single.isDeleted, isTrue);
      api.failDeletion = false;
      await repo.syncPendingTransactions('ledger-1');
      expect(
        (await db.getTransactionsForLedger(
          'ledger-1',
          includeDeleted: true,
        )).where((record) => record.pendingSync),
        isEmpty,
      );
    });

    test(
      'a second save during upload is drained without another trigger',
      () async {
        SharedPreferences.setMockInitialValues({});
        final api = _UndoApiClient();
        final db = DatabaseService();
        final repo = RemoteTransactionRepository(apiClient: api, database: db);
        await repo.saveTransaction(_transaction());
        await api.started.future;
        await repo.saveTransaction(
          _transaction()
            ..uuid = 'local-second'
            ..clientOperationId = 'second-op',
        );
        final sync = repo.syncPendingTransactions('ledger-1');
        api.release.complete();
        await sync;
        expect(api.postPaths, hasLength(2));
        expect(
          (await db.getTransactionsForLedger(
            'ledger-1',
          )).where((record) => record.pendingSync),
          isEmpty,
        );
      },
    );

    test('a newer edit during upload is preserved and uploaded next', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _UndoApiClient();
      final db = DatabaseService();
      final repo = RemoteTransactionRepository(apiClient: api, database: db);
      await repo.saveTransaction(_transaction());
      await api.started.future;
      await repo.saveTransaction(
        _transaction()
          ..amount = 99
          ..note = '修正',
      );
      final sync = repo.syncPendingTransactions('ledger-1');
      api.release.complete();
      await sync;
      expect(api.putData?['amount'], 99);
      expect((await db.getTransactionsForLedger('ledger-1')).single.amount, 99);
    });

    test(
      'accepted create with lost response remains cancelled during refresh',
      () async {
        SharedPreferences.setMockInitialValues({});
        final api = _UndoApiClient()..loseResponse = true;
        final db = DatabaseService();
        final repo = RemoteTransactionRepository(apiClient: api, database: db);
        final record = _transaction()..pendingSync = true;
        await db.saveTransaction(record);
        final upload = repo.syncPendingTransactions('ledger-1');
        await api.started.future;
        await repo.deleteTransaction('ledger-1', record.uuid);
        api.release.complete();
        await upload;
        expect(await repo.getTransactionsForLedger('ledger-1'), isEmpty);
        expect(await db.getTransactionsForLedger('ledger-1'), isEmpty);
        api.loseResponse = false;
        await repo.syncPendingTransactions('ledger-1');
        expect(
          api.deletePaths,
          contains(
            '/api/ledgers/ledger-1/transactions/$_remoteTransactionUuid',
          ),
        );
      },
    );

    test(
      'in-flight undo deletion failure retries only the remote identity',
      () async {
        SharedPreferences.setMockInitialValues({});
        final api = _UndoApiClient()..failDeletion = true;
        final db = DatabaseService();
        final repo = RemoteTransactionRepository(apiClient: api, database: db);
        final record = _transaction()..pendingSync = true;
        await db.saveTransaction(record);
        final upload = repo.syncPendingTransactions('ledger-1');
        await api.started.future;
        await repo.deleteTransaction('ledger-1', record.uuid);
        api.release.complete();
        await upload;
        final pending = (await db.getTransactionsForLedger(
          'ledger-1',
          includeDeleted: true,
        )).where((record) => record.pendingSync);
        expect(pending.map((record) => record.uuid), [_remoteTransactionUuid]);
        api.failDeletion = false;
        await repo.syncPendingTransactions('ledger-1');
        expect(api.postPaths, hasLength(1));
        expect(await db.getTransactionsForLedger('ledger-1'), isEmpty);
      },
    );

    test('keeps local-only ledger transaction on device', () async {
      SharedPreferences.setMockInitialValues({});
      final apiClient = _FakeApiClient([]);
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-only-ledger'
          ..name = '仅本地'
          ..baseCurrencyCode = 'CNY',
      );
      final repository = RemoteTransactionRepository(
        apiClient: apiClient,
        database: database,
      );

      await repository.saveTransaction(
        _transaction()..ledgerUuid = 'local-only-ledger',
      );

      final transaction = (await database.getTransactionsForLedger(
        'local-only-ledger',
      )).single;
      expect(transaction.pendingSync, isFalse);
      expect(transaction.createdByNickname, isNull);
      expect(apiClient.postPaths, isEmpty);
    });

    test('one conflict does not block later pending transactions', () async {
      SharedPreferences.setMockInitialValues({});
      final tokenStore = TokenStore();
      await tokenStore.saveAccountUuid('account-a');
      final database = DatabaseService();
      final conflictStore = ConflictStore();
      final codec = ConflictSnapshotCodec(
        database: database,
        profileStore: const LocalProfileStore(),
      );
      final apiClient = _ConflictThenSuccessApiClient();
      final repository = RemoteTransactionRepository(
        apiClient: apiClient,
        database: database,
        conflictCoordinator: ConflictCoordinator(
          store: conflictStore,
          codec: codec,
          gateway: _UnusedGateway(),
          tokenStore: tokenStore,
        ),
        conflictCodec: codec,
      );
      await database.saveTransaction(
        _transaction()
          ..uuid = _conflictingTransactionUuid
          ..clientOperationId = 'conflict-operation'
          ..version = 2
          ..createdAt = DateTime(2026, 8, 26, 12)
          ..pendingSync = true,
      );
      await database.saveTransaction(
        _transaction()
          ..uuid = _successfulTransactionUuid
          ..clientOperationId = 'success-operation'
          ..version = 1
          ..createdAt = DateTime(2026, 8, 26, 11)
          ..pendingSync = true,
      );

      final result = await repository.syncPendingTransactions('ledger-1');

      expect(result.synced, 1);
      expect(result.error, isNull);
      expect(apiClient.putPaths, [
        '/api/ledgers/ledger-1/transactions/$_conflictingTransactionUuid',
        '/api/ledgers/ledger-1/transactions/$_successfulTransactionUuid',
      ]);
      final conflict = (await conflictStore.readAll()).single;
      expect(conflict.remoteUuid, _conflictingTransactionUuid);
      final cached = await database.getTransactionsForLedger(
        'ledger-1',
        includeDeleted: true,
      );
      final conflicted = cached.singleWhere(
        (item) => item.uuid == _conflictingTransactionUuid,
      );
      expect(conflicted.pendingSync, isFalse);
      expect(conflicted.syncError, isNull);
      final successful = cached.singleWhere(
        (item) => item.uuid == _successfulTransactionUuid,
      );
      expect(successful.pendingSync, isFalse);
      expect(successful.version, 2);
    });
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

const _conflictingTransactionUuid = '11111111111111111111111111111111';
const _successfulTransactionUuid = '22222222222222222222222222222222';

class _ConflictThenSuccessApiClient extends ApiClient {
  _ConflictThenSuccessApiClient() : super(tokenStore: TokenStore());

  final putPaths = <String>[];

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    putPaths.add(path);
    final uuid = path.split('/').last;
    if (uuid == _conflictingTransactionUuid) {
      throw const ApiException(
        code: 409001,
        statusCode: 409,
        message: '流水已被修改',
        conflict: ApiConflictPayload(
          entityType: ConflictEntityType.transaction,
          entityUuid: _conflictingTransactionUuid,
          submittedVersion: 2,
          remoteVersion: 3,
          remoteDeleted: false,
          remoteSnapshot: {
            'uuid': _conflictingTransactionUuid,
            'ledgerUuid': 'ledger-1',
            'type': 0,
            'amount': 30.0,
            'currencyCode': 'CNY',
            'category': '餐饮',
            'note': '云端修改',
            'happenedAt': '2026-08-26T12:00:00.000',
            'personUuids': ['person-1'],
            'version': 3,
          },
        ),
      );
    }
    return fromJson!({
      ..._transactionJson(uuid),
      'clientOperationId': 'success-operation',
      'version': 2,
    });
  }
}

class _UnusedGateway implements ConflictResolutionGateway {
  @override
  Future<ConflictMutationResult> submit(ConflictRecord record) {
    throw UnimplementedError();
  }
}

class _UndoApiClient extends _FakeApiClient {
  _UndoApiClient() : super([]);
  bool failDeletion = false;
  bool loseResponse = false;
  Map<String, dynamic>? putData;
  final postKeys = <String?>[];
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async => fromJson!({
    'total': 1,
    'records': [
      {
        ..._transactionJson(_remoteTransactionUuid),
        'clientOperationId': 'client-op-1',
      },
    ],
  });
  @override
  Future<void> deleteVoid(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) async {
    if (failDeletion) throw StateError('offline');
    await super.deleteVoid(path, data: data, idempotencyKey: idempotencyKey);
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    putPaths.add(path);
    putData = data! as Map<String, dynamic>;
    return fromJson!({
      ..._transactionJson(path.split('/').last),
      ...putData!,
      'version': 2,
    });
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    postPaths.add(path);
    postKeys.add(idempotencyKey);
    if (!started.isCompleted) started.complete();
    await release.future;
    if (loseResponse) throw StateError('response lost after acceptance');
    final recordUuid = idempotencyKey == 'second-op'
        ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        : _remoteTransactionUuid;
    return fromJson!({
      ..._transactionJson(recordUuid),
      'clientOperationId': idempotencyKey,
    });
  }
}
