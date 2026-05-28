import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
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
          ..name = '张三'
          ..avatar = '🙂',
      );
      await database.savePerson(
        Person()
          ..uuid = 'person-2'
          ..name = '李四'
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
      expect(people.single.name, '张三');
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
}
