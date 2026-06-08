import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/providers/ledger_stats_calculator.dart';

void main() {
  group('calculateLedgerStats', () {
    test('aggregates income, expense, and balance per ledger', () {
      final stats = calculateLedgerStats(
        ledgerUuids: ['ledger-a', 'ledger-b'],
        ledgersByUuid: _ledgersByUuid(['ledger-a', 'ledger-b']),
        transactions: [
          _transaction(ledgerUuid: 'ledger-a', type: 0, amount: 20),
          _transaction(ledgerUuid: 'ledger-a', type: 1, amount: 75),
          _transaction(ledgerUuid: 'ledger-a', type: 0, amount: 5.5),
          _transaction(ledgerUuid: 'ledger-b', type: 1, amount: 12),
        ],
      );

      expect(stats['ledger-a']?['expense'], 25.5);
      expect(stats['ledger-a']?['income'], 75);
      expect(stats['ledger-a']?['balance'], 49.5);
      expect(stats['ledger-b']?['expense'], 0);
      expect(stats['ledger-b']?['income'], 12);
      expect(stats['ledger-b']?['balance'], 12);
    });

    test('keeps empty ledgers in the result', () {
      final stats = calculateLedgerStats(
        ledgerUuids: ['empty-ledger'],
        ledgersByUuid: _ledgersByUuid(['empty-ledger']),
        transactions: const [],
      );

      expect(stats['empty-ledger'], {'expense': 0, 'income': 0, 'balance': 0});
    });

    test('ignores transactions for unknown ledgers', () {
      final stats = calculateLedgerStats(
        ledgerUuids: ['known-ledger'],
        ledgersByUuid: _ledgersByUuid(['known-ledger']),
        transactions: [
          _transaction(ledgerUuid: 'unknown-ledger', type: 1, amount: 999),
        ],
      );

      expect(stats['known-ledger']?['income'], 0);
      expect(stats.containsKey('unknown-ledger'), isFalse);
    });

    test('converts foreign currency transactions to CNY', () {
      final ledger = _ledger('ledger-a')
        ..baseCurrencyCode = 'USD'
        ..exchangeRateToCNY = 7.2;
      final stats = calculateLedgerStats(
        ledgerUuids: ['ledger-a'],
        ledgersByUuid: {'ledger-a': ledger},
        transactions: [
          _transaction(
            ledgerUuid: 'ledger-a',
            type: 0,
            amount: 10,
            currencyCode: 'USD',
          ),
          _transaction(ledgerUuid: 'ledger-a', type: 1, amount: 100),
        ],
      );

      expect(stats['ledger-a']?['expense'], 72);
      expect(stats['ledger-a']?['income'], 100);
      expect(stats['ledger-a']?['balance'], 28);
    });
  });
}

TransactionRecord _transaction({
  required String ledgerUuid,
  required int type,
  required double amount,
  String currencyCode = 'CNY',
}) {
  return TransactionRecord()
    ..uuid = '$ledgerUuid-$type-$amount'
    ..ledgerUuid = ledgerUuid
    ..type = type
    ..amount = amount
    ..currencyCode = currencyCode
    ..category = '默认'
    ..personUuids = const []
    ..note = ''
    ..createdAt = DateTime(2026);
}

Map<String, Ledger> _ledgersByUuid(List<String> ledgerUuids) {
  return {for (final uuid in ledgerUuids) uuid: _ledger(uuid)};
}

Ledger _ledger(String uuid) {
  return Ledger()
    ..uuid = uuid
    ..name = uuid
    ..baseCurrencyCode = 'CNY'
    ..exchangeRateToCNY = 1;
}
