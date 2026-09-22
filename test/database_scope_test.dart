import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('account scope reads guest data but not another account data', () async {
    final guest = DatabaseService(scope: const LocalDataScope.guest());
    final accountA = DatabaseService(
      scope: LocalDataScope.account('account-a'),
    );
    final accountB = DatabaseService(
      scope: LocalDataScope.account('account-b'),
    );

    await guest.saveLedger(_ledger('guest-ledger'));
    await accountA.saveLedger(
      _ledger('a-ledger')..localAccountUuid = 'account-a',
    );

    final accountALedgers = await accountA.getAllLedgers();
    final accountBLedgers = await accountB.getAllLedgers();

    expect(
      accountALedgers.map((ledger) => ledger.uuid),
      containsAll(<String>['guest-ledger', 'a-ledger']),
    );
    expect(
      accountBLedgers.map((ledger) => ledger.uuid),
      contains('guest-ledger'),
    );
    expect(
      accountBLedgers.map((ledger) => ledger.uuid),
      isNot(contains('a-ledger')),
    );
  });

  test(
    'migrates legacy cloud caches only into their known account scope',
    () async {
      SharedPreferences.setMockInitialValues({
        'local_store.ledgers.v1': jsonEncode([
          {
            'uuid': 'guest-ledger',
            'name': '离线账本',
            'baseCurrencyCode': 'CNY',
            'personUuids': ['guest-person'],
          },
          {
            'uuid': 'account-ledger',
            'name': '账号 A 缓存',
            'baseCurrencyCode': 'CNY',
            'cacheOwnerUserUuid': 'account-a',
            'personUuids': ['account-person'],
            'cloudPolicy': 'cloudManaged',
          },
          {
            'uuid': 'ambiguous-ledger',
            'name': '未知缓存',
            'baseCurrencyCode': 'CNY',
            'personUuids': ['ambiguous-person'],
            'cloudPolicy': 'cloudManaged',
          },
        ]),
        'local_store.people.v1': jsonEncode([
          {'uuid': 'guest-person', 'name': '离线人员'},
          {'uuid': 'account-person', 'name': '账号人员'},
          {'uuid': 'ambiguous-person', 'name': '未知人员'},
        ]),
        'local_store.transactions.v1': jsonEncode([
          {
            'uuid': 'account-transaction',
            'ledgerUuid': 'account-ledger',
            'amount': 8,
            'currencyCode': 'CNY',
            'category': '餐饮',
            'note': '',
            'createdAt': '2026-09-22T08:00:00.000',
          },
        ]),
      });

      final guest = DatabaseService();
      final accountA = DatabaseService(
        scope: LocalDataScope.account('account-a'),
      );
      final accountB = DatabaseService(
        scope: LocalDataScope.account('account-b'),
      );

      expect(
        (await guest.getAllLedgers()).map((ledger) => ledger.uuid),
        contains('guest-ledger'),
      );
      expect(
        (await guest.getAllLedgers()).map((ledger) => ledger.uuid),
        isNot(contains('ambiguous-ledger')),
      );
      expect(
        (await accountA.getAllLedgers()).map((ledger) => ledger.uuid),
        containsAll(['guest-ledger', 'account-ledger']),
      );
      expect(
        (await accountB.getAllLedgers()).map((ledger) => ledger.uuid),
        contains('guest-ledger'),
      );
      expect(
        (await accountB.getAllLedgers()).map((ledger) => ledger.uuid),
        isNot(contains('account-ledger')),
      );
      expect(
        (await accountA.getTransactionsForLedger('account-ledger')).single.uuid,
        'account-transaction',
      );
    },
  );

  test('people and transactions follow their ledger scope', () async {
    final guest = DatabaseService(scope: const LocalDataScope.guest());
    final accountA = DatabaseService(
      scope: LocalDataScope.account('account-a'),
    );
    final accountB = DatabaseService(
      scope: LocalDataScope.account('account-b'),
    );
    final ledger = _ledger('a-ledger')..localAccountUuid = 'account-a';

    await accountA.saveLedger(ledger);
    await accountA.savePerson(
      Person()
        ..uuid = 'a-person'
        ..name = 'A 的人员'
        ..pendingLedgerUuid = ledger.uuid
        ..localAccountUuid = 'account-a',
    );
    await accountA.saveTransaction(
      TransactionRecord()
        ..uuid = 'a-transaction'
        ..ledgerUuid = ledger.uuid
        ..amount = 10
        ..currencyCode = 'CNY'
        ..category = '餐饮'
        ..note = ''
        ..createdAt = DateTime(2026, 9, 22)
        ..localAccountUuid = 'account-a',
    );

    expect(
      (await accountA.getAllPeople()).map((person) => person.uuid),
      contains('a-person'),
    );
    expect(
      (await accountA.getTransactionsForLedger(
        ledger.uuid,
      )).map((transaction) => transaction.uuid),
      contains('a-transaction'),
    );
    expect(
      (await accountB.getAllPeople()).map((person) => person.uuid),
      isNot(contains('a-person')),
    );
    expect(
      (await accountB.getTransactionsForLedger(
        ledger.uuid,
      )).map((transaction) => transaction.uuid),
      isNot(contains('a-transaction')),
    );
    expect(
      (await guest.getAllPeople()).map((person) => person.uuid),
      isNot(contains('a-person')),
    );
  });

  test(
    'claiming a guest ledger moves its complete local graph to an account',
    () async {
      final guest = DatabaseService(scope: const LocalDataScope.guest());
      final accountA = DatabaseService(
        scope: LocalDataScope.account('account-a'),
      );
      final ledger = _ledger('guest-ledger');
      await guest.saveLedger(ledger);
      await guest.savePerson(
        Person()
          ..uuid = 'guest-person'
          ..name = '本地人员'
          ..pendingLedgerUuid = ledger.uuid,
      );
      await guest.saveTransaction(
        TransactionRecord()
          ..uuid = 'guest-transaction'
          ..ledgerUuid = ledger.uuid
          ..amount = 12
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..note = ''
          ..createdAt = DateTime(2026, 9, 22),
      );

      await accountA.claimLedger(ledger.uuid, 'account-a');

      final claimed = (await accountA.getAllLedgers()).singleWhere(
        (item) => item.uuid == ledger.uuid,
      );
      expect(claimed.localAccountUuid, 'account-a');
      expect(claimed.claimPending, isTrue);
      expect(
        (await guest.getAllLedgers()).map((item) => item.uuid),
        isNot(contains(ledger.uuid)),
      );
      expect(
        (await accountA.getAllPeople()).map((item) => item.uuid),
        contains('guest-person'),
      );
      expect(
        (await accountA.getTransactionsForLedger(
          ledger.uuid,
        )).map((item) => item.uuid),
        contains('guest-transaction'),
      );
    },
  );
}

Ledger _ledger(String uuid) {
  return Ledger()
    ..uuid = uuid
    ..name = uuid
    ..baseCurrencyCode = 'CNY';
}
