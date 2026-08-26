import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';

void main() {
  group('DatabaseService', () {
    late DatabaseService database;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      database = DatabaseService();
    });

    test('initializes the default local person', () async {
      await database.init();

      final people = await database.getAllPeople();

      expect(people, hasLength(1));
      expect(people.single.uuid, 'self');
      expect(people.single.name, '我');
      expect(people.single.avatar, '🧑');
    });

    test('normalizes legacy default local person', () async {
      await database.savePerson(
        Person()
          ..uuid = 'self'
          ..name = '本人'
          ..avatar = '😎',
      );

      await database.init();

      final people = await database.getAllPeople();
      expect(people.single.name, '我');
      expect(people.single.avatar, '🧑');
    });

    test('syncs local self person from saved local profile on init', () async {
      await const LocalProfileStore().save(
        const LocalProfile(nickname: 'Simon', avatarIcon: 'star'),
      );
      await database.savePerson(
        Person()
          ..uuid = 'self'
          ..name = '本人'
          ..avatar = '😎',
      );

      await database.init();

      final people = await database.getAllPeople();
      expect(people.single.name, 'Simon');
      expect(people.single.avatar, '⭐');
    });

    test('stores ledgers and transactions in local preferences', () async {
      await database.init();
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-1'
          ..name = '家庭账本'
          ..baseCurrencyCode = 'CNY'
          ..sortOrder = 1,
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'tx-older'
          ..ledgerUuid = 'ledger-1'
          ..type = 0
          ..payerPersonUuid = 'p1'
          ..amount = 12
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..note = ''
          ..createdAt = DateTime(2026, 5, 21),
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'tx-newer'
          ..ledgerUuid = 'ledger-1'
          ..type = 1
          ..amount = 20
          ..currencyCode = 'CNY'
          ..category = '收入'
          ..note = ''
          ..createdAt = DateTime(2026, 5, 22),
      );

      final ledgers = await database.getAllLedgers();
      final transactions = await database.getTransactionsForLedger('ledger-1');

      expect(ledgers.single.name, '家庭账本');
      expect(transactions.last.payerPersonUuid, 'p1');
      expect(transactions.map((transaction) => transaction.uuid), [
        'tx-newer',
        'tx-older',
      ]);
    });

    test('soft deletes a ledger and its transactions', () async {
      await database.init();
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-1'
          ..name = '家庭账本'
          ..baseCurrencyCode = 'CNY',
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'tx-1'
          ..ledgerUuid = 'ledger-1'
          ..type = 0
          ..amount = 12
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..note = ''
          ..createdAt = DateTime(2026, 5, 22),
      );

      await database.deleteLedger('ledger-1');

      expect(await database.getAllLedgers(), isEmpty);
      expect(await database.getTransactionsForLedger('ledger-1'), isEmpty);
      expect(
        await database.getTransactionsForLedger(
          'ledger-1',
          includeDeleted: true,
        ),
        hasLength(1),
      );
    });

    test('hides a ledger without deleting its transactions', () async {
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-1'
          ..name = 'shared'
          ..baseCurrencyCode = 'CNY',
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'tx-1'
          ..ledgerUuid = 'ledger-1'
          ..type = 0
          ..amount = 12
          ..currencyCode = 'CNY'
          ..category = 'food'
          ..note = ''
          ..createdAt = DateTime(2026, 6, 8),
      );

      await database.hideLedger('ledger-1');

      expect(await database.getAllLedgers(), isEmpty);
      expect(await database.getTransactionsForLedger('ledger-1'), hasLength(1));
      final hiddenLedger = (await database.getAllLedgers(
        includeDeleted: true,
      )).single;
      expect(hiddenLedger.isDeleted, isTrue);
    });

    test('returns ledgers with the newest sort order first', () async {
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-older'
          ..name = '旧账本'
          ..baseCurrencyCode = 'CNY'
          ..sortOrder = 0,
      );
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-newer'
          ..name = '新账本'
          ..baseCurrencyCode = 'CNY'
          ..sortOrder = 1,
      );

      final ledgers = await database.getAllLedgers();

      expect(ledgers.map((ledger) => ledger.uuid), [
        'ledger-newer',
        'ledger-older',
      ]);
    });

    test('defaults missing optimistic versions to one', () async {
      SharedPreferences.setMockInitialValues({
        'local_store.ledgers.v1': jsonEncode([
          {'uuid': 'ledger-legacy', 'name': '旧账本', 'baseCurrencyCode': 'CNY'},
        ]),
        'local_store.people.v1': jsonEncode([
          {'uuid': 'person-legacy', 'name': '旧参与人'},
        ]),
        'local_store.transactions.v1': jsonEncode([
          {
            'uuid': 'transaction-legacy',
            'ledgerUuid': 'ledger-legacy',
            'amount': 12,
            'currencyCode': 'CNY',
            'category': '餐饮',
            'createdAt': '2026-08-26T08:00:00.000',
          },
        ]),
      });

      final legacyDatabase = DatabaseService();
      expect((await legacyDatabase.getAllLedgers()).single.version, 1);
      expect((await legacyDatabase.getAllPeople()).single.version, 1);
      expect(
        (await legacyDatabase.getTransactionsForLedger(
          'ledger-legacy',
        )).single.version,
        1,
      );
    });

    test('round trips optimistic versions for cached entities', () async {
      final ledger = Ledger()
        ..uuid = 'ledger-versioned'
        ..name = '版本账本'
        ..baseCurrencyCode = 'CNY'
        ..version = 5
        ..members = [
          const LedgerMemberSummary(
            uuid: 'member-versioned',
            nickname: '成员',
            version: 4,
          ),
        ];
      final person = Person()
        ..uuid = 'person-versioned'
        ..name = '版本参与人'
        ..version = 3;
      final transaction = TransactionRecord()
        ..uuid = 'transaction-versioned'
        ..ledgerUuid = ledger.uuid
        ..amount = 21
        ..currencyCode = 'CNY'
        ..category = '交通'
        ..note = ''
        ..createdAt = DateTime(2026, 8, 26)
        ..version = 6;

      await database.saveLedger(ledger);
      await database.savePerson(person);
      await database.saveTransaction(transaction);

      expect((await database.getAllLedgers()).single.version, 5);
      expect((await database.getAllLedgers()).single.members.single.version, 4);
      expect((await database.getAllPeople()).single.version, 3);
      expect(
        (await database.getTransactionsForLedger(ledger.uuid)).single.version,
        6,
      );
    });
  });
}
