import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/ledger_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/person_repository.dart';

void main() {
  test('RemoteLedgerRepository falls back to cached ledgers offline', () async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    await database.saveLedger(
      Ledger()
        ..uuid = 'ledger-1'
        ..name = '离线账本'
        ..baseCurrencyCode = 'CNY'
        ..exchangeRateToCNY = 1
        ..personUuids = ['person-1'],
    );

    final repository = RemoteLedgerRepository(
      apiClient: _OfflineApiClient(),
      database: database,
    );

    final ledgers = await repository.getAllLedgers();

    expect(ledgers, hasLength(1));
    expect(ledgers.single.uuid, 'ledger-1');
    expect(ledgers.single.personUuids, ['person-1']);
  });

  test('RemoteLedgerRepository caches people from batch ledger list', () async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final apiClient = _LedgerCreateApiClient();
    final repository = RemoteLedgerRepository(
      apiClient: apiClient,
      database: database,
    );

    final ledgers = await repository.getAllLedgers();
    final people = await database.getAllPeople();

    expect(apiClient.getPaths, ['/api/ledgers', '/api/ledgers/people']);
    expect(ledgers.single.personUuids, [_remotePersonUuid]);
    expect(people.single.uuid, _remotePersonUuid);
    expect(people.single.name, '本人');
    expect(people.single.avatar, '😎');
  });

  test('RemoteLedgerRepository keeps cached local ledger order', () async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    await database.saveLedger(
      Ledger()
        ..uuid = _remoteLedgerUuid
        ..name = '第二个账本'
        ..baseCurrencyCode = 'CNY'
        ..sortOrder = 1,
    );
    await database.saveLedger(
      Ledger()
        ..uuid = _anotherRemoteLedgerUuid
        ..name = '第一个账本'
        ..baseCurrencyCode = 'CNY'
        ..sortOrder = 0,
    );
    final repository = RemoteLedgerRepository(
      apiClient: _OrderedLedgersApiClient(),
      database: database,
    );

    final ledgers = await repository.getAllLedgers();

    expect(ledgers.map((ledger) => ledger.uuid), [
      _anotherRemoteLedgerUuid,
      _remoteLedgerUuid,
    ]);
  });

  test(
    'RemoteLedgerRepository creates ledger locally when cloud create is offline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      final repository = RemoteLedgerRepository(
        apiClient: _OfflineApiClient(),
        database: database,
      );

      await repository.createLedgerWithPeople(
        Ledger()
          ..uuid = 'local-ledger-1'
          ..name = '离线新账本'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1,
        [
          Person()
            ..uuid = 'local-person-1'
            ..name = '本人'
            ..avatar = '😎',
        ],
      );

      final ledgers = await database.getAllLedgers();
      final people = await database.getAllPeople();

      expect(ledgers.single.uuid, 'local-ledger-1');
      expect(ledgers.single.isLocalTemporary, isTrue);
      expect(ledgers.single.syncedRemoteUuid, isNull);
      expect(ledgers.single.cloudPolicy, LedgerCloudPolicy.uploadRequested);
      expect(ledgers.single.personUuids, ['local-person-1']);
      expect(people.single.uuid, 'local-person-1');
    },
  );

  test(
    'RemoteLedgerRepository does not upload local-only ledger automatically',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-only-ledger'
          ..name = '仅本地账本'
          ..baseCurrencyCode = 'CNY',
      );
      final apiClient = _LedgerCreateApiClient();
      final repository = RemoteLedgerRepository(
        apiClient: apiClient,
        database: database,
      );

      await repository.syncPendingWrites();

      expect(apiClient.postPaths, isEmpty);
      expect((await database.getAllLedgers()).single.syncedRemoteUuid, isNull);
    },
  );

  test(
    'RemoteLedgerRepository keeps local temporary ledger after syncing remote copy',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.savePerson(
        Person()
          ..uuid = 'local-person-1'
          ..name = '本人'
          ..avatar = '😎',
      );
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-ledger-1'
          ..name = '离线新账本'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1
          ..cloudPolicy = LedgerCloudPolicy.uploadRequested
          ..personUuids = ['local-person-1'],
      );

      final repository = RemoteLedgerRepository(
        apiClient: _LedgerCreateApiClient(),
        database: database,
      );

      final ledgers = await repository.getAllLedgers();
      final cachedLedgers = await database.getAllLedgers();

      expect(ledgers, hasLength(1));
      expect(ledgers.single.uuid, 'local-ledger-1');
      final localLedger = cachedLedgers.firstWhere(
        (ledger) => ledger.uuid == 'local-ledger-1',
      );
      expect(localLedger.syncedRemoteUuid, _remoteLedgerUuid);
      expect(localLedger.isLocalTemporary, isTrue);
      final localPerson = (await database.getAllPeople()).firstWhere(
        (person) => person.uuid == 'local-person-1',
      );
      expect(localPerson.syncedRemoteUuid, _remotePersonUuid);
      final cachedVisibleLedgers = await repository.getCachedLedgers();
      expect(cachedVisibleLedgers, hasLength(1));
      expect(cachedVisibleLedgers.single.uuid, 'local-ledger-1');
    },
  );

  test(
    'RemoteLedgerRepository queues historical transactions when syncing selected local ledger',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.savePerson(
        Person()
          ..uuid = 'local-person-1'
          ..name = '本人'
          ..avatar = '😎',
      );
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-ledger-1'
          ..name = '待导入账本'
          ..baseCurrencyCode = 'CNY'
          ..cloudPolicy = LedgerCloudPolicy.uploadRequested
          ..personUuids = ['local-person-1'],
      );
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-ledger-2'
          ..name = '暂不导入账本'
          ..baseCurrencyCode = 'CNY'
          ..personUuids = ['local-person-1'],
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'local-transaction-1'
          ..ledgerUuid = 'local-ledger-1'
          ..type = 0
          ..amount = 12
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..note = ''
          ..personUuids = ['local-person-1']
          ..createdAt = DateTime(2026),
      );
      final repository = RemoteLedgerRepository(
        apiClient: _LedgerCreateApiClient(),
        database: database,
      );

      await repository.syncPendingWrites(ledgerUuid: 'local-ledger-1');

      final ledgers = await database.getAllLedgers();
      expect(
        ledgers
            .firstWhere((ledger) => ledger.uuid == 'local-ledger-1')
            .syncedRemoteUuid,
        _remoteLedgerUuid,
      );
      expect(
        ledgers
            .firstWhere((ledger) => ledger.uuid == 'local-ledger-2')
            .syncedRemoteUuid,
        isNull,
      );
      final transaction = (await database.getTransactionsForLedger(
        'local-ledger-1',
      )).single;
      expect(transaction.pendingSync, isTrue);
      expect(transaction.clientOperationId, 'local-transaction-1');
    },
  );

  test(
    'RemoteLedgerRepository saves remote ledger edits locally while offline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = _remoteLedgerUuid
          ..name = '旧名称'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1,
      );
      final repository = RemoteLedgerRepository(
        apiClient: _OfflineApiClient(),
        database: database,
      );

      await repository.saveLedger(
        Ledger()
          ..uuid = _remoteLedgerUuid
          ..name = '新名称'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1,
      );

      final ledger = (await database.getAllLedgers()).single;
      expect(ledger.name, '新名称');
      expect(ledger.pendingSync, isTrue);
      expect(ledger.syncError, isNotEmpty);
    },
  );

  test(
    'RemoteLedgerRepository deletes remote ledger locally while offline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = _remoteLedgerUuid
          ..name = '云端账本'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1,
      );
      final repository = RemoteLedgerRepository(
        apiClient: _OfflineApiClient(),
        database: database,
      );

      await repository.deleteLedger(_remoteLedgerUuid);

      expect(await database.getAllLedgers(), isEmpty);
      final deleted = (await database.getAllLedgers(
        includeDeleted: true,
      )).single;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.pendingSync, isTrue);
      expect(deleted.syncError, isNotEmpty);
    },
  );

  test(
    'RemotePersonRepository falls back to cached ledger people offline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-1'
          ..name = '离线账本'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1
          ..personUuids = ['person-1'],
      );
      await database.savePerson(
        Person()
          ..uuid = 'person-1'
          ..name = '历史人员'
          ..avatar = '🙂',
      );
      await database.savePerson(
        Person()
          ..uuid = 'person-2'
          ..name = '其他人员'
          ..avatar = '😎',
      );

      final ledgerRepository = RemoteLedgerRepository(
        apiClient: _OfflineApiClient(),
        database: database,
      );
      final repository = RemotePersonRepository(
        apiClient: _OfflineApiClient(),
        ledgerRepository: ledgerRepository,
        database: database,
      );

      final people = await repository.getAllPeople(ledgerUuid: 'ledger-1');

      expect(people, hasLength(1));
      expect(people.single.uuid, 'person-1');
      expect(people.single.name, '历史人员');
    },
  );

  test('RemotePersonRepository saves person locally while offline', () async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledgerRepository = RemoteLedgerRepository(
      apiClient: _OfflineApiClient(),
      database: database,
    );
    final repository = RemotePersonRepository(
      apiClient: _OfflineApiClient(),
      ledgerRepository: ledgerRepository,
      database: database,
    );

    await repository.savePerson(
      Person()
        ..uuid = 'local-person-1'
        ..name = '离线人员'
        ..avatar = '🙂',
      ledgerUuid: _remoteLedgerUuid,
    );

    final person = (await database.getAllPeople()).single;
    expect(person.name, '离线人员');
    expect(person.pendingSync, isTrue);
    expect(person.pendingLedgerUuid, _remoteLedgerUuid);
    expect(person.syncError, isNotEmpty);
  });

  test(
    'RemotePersonRepository keeps local-only ledger person on device',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-only-ledger'
          ..name = '仅本地'
          ..baseCurrencyCode = 'CNY',
      );
      final apiClient = _PersonCreateApiClient();
      final ledgerRepository = RemoteLedgerRepository(
        apiClient: apiClient,
        database: database,
      );
      final repository = RemotePersonRepository(
        apiClient: apiClient,
        ledgerRepository: ledgerRepository,
        database: database,
      );

      await repository.savePerson(
        Person()
          ..uuid = 'local-person'
          ..name = '本地人员',
        ledgerUuid: 'local-only-ledger',
      );

      final person = (await database.getAllPeople()).single;
      expect(person.pendingSync, isFalse);
      expect(person.pendingLedgerUuid, isNull);
      expect(apiClient.postPaths, isEmpty);
    },
  );

  test(
    'RemotePersonRepository uploads person through mapped remote ledger',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-ledger-1'
          ..syncedRemoteUuid = _remoteLedgerUuid
          ..name = '离线新账本'
          ..baseCurrencyCode = 'CNY'
          ..personUuids = ['local-person-1'],
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'local-tx-1'
          ..ledgerUuid = 'local-ledger-1'
          ..type = 0
          ..payerPersonUuid = 'local-person-1'
          ..amount = 12
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..personUuids = ['local-person-1']
          ..note = ''
          ..createdAt = DateTime(2026, 6, 1),
      );
      final apiClient = _PersonCreateApiClient();
      final ledgerRepository = RemoteLedgerRepository(
        apiClient: apiClient,
        database: database,
      );
      final repository = RemotePersonRepository(
        apiClient: apiClient,
        ledgerRepository: ledgerRepository,
        database: database,
      );

      await repository.savePerson(
        Person()
          ..uuid = 'local-person-1'
          ..name = '离线人员'
          ..avatar = '🙂',
        ledgerUuid: 'local-ledger-1',
      );

      expect(apiClient.postPaths, ['/api/ledgers/$_remoteLedgerUuid/people']);
      final ledger = (await database.getAllLedgers()).single;
      final transaction = (await database.getTransactionsForLedger(
        'local-ledger-1',
      )).single;
      expect(ledger.personUuids, [_remotePersonUuid]);
      expect(transaction.personUuids, [_remotePersonUuid]);
      expect(transaction.payerPersonUuid, _remotePersonUuid);
    },
  );

  test(
    'RemotePersonRepository keeps deleted people referenced by history offline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-1'
          ..name = '离线账本'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1
          ..personUuids = const [],
      );
      await database.savePerson(
        Person()
          ..uuid = 'person-1'
          ..name = '历史人员'
          ..avatar = '🙂'
          ..isDeleted = true,
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'tx-1'
          ..ledgerUuid = 'ledger-1'
          ..type = 0
          ..amount = 12
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..personUuids = ['person-1']
          ..note = ''
          ..createdAt = DateTime(2026, 5, 28),
      );

      final ledgerRepository = RemoteLedgerRepository(
        apiClient: _OfflineApiClient(),
        database: database,
      );
      final repository = RemotePersonRepository(
        apiClient: _OfflineApiClient(),
        ledgerRepository: ledgerRepository,
        database: database,
      );

      final people = await repository.getAllPeople(
        includeDeleted: true,
        ledgerUuid: 'ledger-1',
      );

      expect(people, hasLength(1));
      expect(people.single.uuid, 'person-1');
      expect(people.single.isDeleted, isTrue);
    },
  );
}

class _OfflineApiClient extends ApiClient {
  _OfflineApiClient() : super(tokenStore: TokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) {
    throw Exception('offline');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) {
    throw Exception('offline');
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) {
    throw Exception('offline');
  }

  @override
  Future<void> deleteVoid(String path, {Object? data, String? idempotencyKey}) {
    throw Exception('offline');
  }
}

const _remoteLedgerUuid = '0123456789abcdef0123456789abcdef';
const _anotherRemoteLedgerUuid = 'fedcba9876543210fedcba9876543210';
const _remotePersonUuid = 'abcdef0123456789abcdef0123456789';

class _LedgerCreateApiClient extends ApiClient {
  _LedgerCreateApiClient() : super(tokenStore: TokenStore());

  final List<String> getPaths = [];
  final List<String> postPaths = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    getPaths.add(path);
    if (path == '/api/ledgers') {
      return fromJson!(<Map<String, dynamic>>[
        {
          'uuid': _remoteLedgerUuid,
          'name': '离线新账本',
          'baseCurrencyCode': 'CNY',
          'exchangeRateToCny': 1,
          'role': 'owner',
          'memberCount': 1,
          'members': const [],
        },
      ]);
    }
    if (path == '/api/ledgers/people') {
      return fromJson!({
        _remoteLedgerUuid: [
          {
            'uuid': _remotePersonUuid,
            'name': '本人',
            'avatar': '😎',
            'linkedUserUuid': null,
          },
        ],
      });
    }
    throw UnimplementedError(path);
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    postPaths.add(path);
    if (path != '/api/ledgers/with-people') {
      throw UnimplementedError(path);
    }
    return fromJson!({
      'ledger': {
        'uuid': _remoteLedgerUuid,
        'name': '离线新账本',
        'baseCurrencyCode': 'CNY',
        'exchangeRateToCny': 1,
        'role': 'owner',
        'memberCount': 1,
        'members': const [],
      },
      'people': [
        {
          'uuid': _remotePersonUuid,
          'name': '本人',
          'avatar': '😎',
          'linkedUserUuid': null,
        },
      ],
    });
  }
}

class _PersonCreateApiClient extends ApiClient {
  _PersonCreateApiClient() : super(tokenStore: TokenStore());

  final List<String> postPaths = [];

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    postPaths.add(path);
    return fromJson!({
      'uuid': _remotePersonUuid,
      'name': '离线人员',
      'avatar': '🙂',
      'linkedUserUuid': null,
    });
  }
}

class _OrderedLedgersApiClient extends ApiClient {
  _OrderedLedgersApiClient() : super(tokenStore: TokenStore());

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    if (path == '/api/ledgers') {
      return fromJson!([
        {'uuid': _remoteLedgerUuid, 'name': '第二个账本', 'baseCurrencyCode': 'CNY'},
        {
          'uuid': _anotherRemoteLedgerUuid,
          'name': '第一个账本',
          'baseCurrencyCode': 'CNY',
        },
      ]);
    }
    if (path == '/api/ledgers/people') {
      return fromJson!({
        _remoteLedgerUuid: const [],
        _anotherRemoteLedgerUuid: const [],
      });
    }
    throw UnimplementedError(path);
  }
}
