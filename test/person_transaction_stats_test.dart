import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/person_transaction_stats.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';

void main() {
  group('calculatePersonTransactionStats', () {
    test('keeps shared pool expenses compatible with existing behavior', () {
      final stats = calculatePersonTransactionStats([
        _transaction(amount: 100, people: ['a', 'b']),
      ]);

      expect(stats.personBalances['a'], -50);
      expect(stats.personBalances['b'], -50);
      expect(stats.settlements, isEmpty);
    });

    test('calculates payer settlement for paid-by-person expenses', () {
      final stats = calculatePersonTransactionStats([
        _transaction(amount: 300, people: ['a', 'b', 'c'], payer: 'a'),
      ]);

      expect(stats.personBalances['a'], 200);
      expect(stats.personBalances['b'], -100);
      expect(stats.personBalances['c'], -100);
      expect(stats.settlements, hasLength(2));
      expect(stats.settlements.map((item) => item.fromPersonUuid), ['b', 'c']);
      expect(stats.settlements.map((item) => item.toPersonUuid), ['a', 'a']);
      expect(stats.settlements.map((item) => item.amount), [100, 100]);
    });

    test('allows payer to be outside the people who used the expense', () {
      final stats = calculatePersonTransactionStats([
        _transaction(amount: 300, people: ['b', 'c'], payer: 'a'),
      ]);

      expect(stats.personBalances['a'], 300);
      expect(stats.personBalances['b'], -150);
      expect(stats.personBalances['c'], -150);
      expect(stats.settlements.map((item) => item.fromPersonUuid), ['b', 'c']);
    });

    test('nets opposite settlements between two people', () {
      final stats = calculatePersonTransactionStats([
        _transaction(amount: 100, people: ['b'], payer: 'a'),
        _transaction(amount: 70, people: ['a'], payer: 'b'),
      ]);

      expect(stats.settlements, hasLength(1));
      expect(stats.settlements.single.fromPersonUuid, 'b');
      expect(stats.settlements.single.toPersonUuid, 'a');
      expect(stats.settlements.single.amount, 30);
    });
  });
}

TransactionRecord _transaction({
  required double amount,
  required List<String> people,
  String? payer,
}) {
  return TransactionRecord()
    ..uuid = DateTime.now().microsecondsSinceEpoch.toString()
    ..ledgerUuid = 'ledger-1'
    ..type = 0
    ..payerPersonUuid = payer
    ..amount = amount
    ..currencyCode = 'CNY'
    ..category = '餐饮'
    ..personUuids = people
    ..note = ''
    ..createdAt = DateTime(2026, 5, 23);
}
