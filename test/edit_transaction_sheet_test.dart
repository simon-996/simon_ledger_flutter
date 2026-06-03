import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/edit_transaction_sheet.dart';

void main() {
  testWidgets(
    'edit transaction sheet keeps primary controls usable on mobile',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = DatabaseService();
      final ledger = await _saveLedgerFixture(database);
      final transaction = _transactionFixture(ledger);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EditTransactionSheet(
                transaction: transaction,
                ledger: ledger,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('编辑明细'), findsOneWidget);
      expect(find.text('旅行账本 · ${ledger.displayCode}'), findsOneWidget);
      expect(find.text('支出'), findsOneWidget);
      expect(find.text('收入'), findsOneWidget);
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('共同钱包'), findsOneWidget);
      expect(find.text('某人代付'), findsOneWidget);
      expect(find.text('Simon'), findsOneWidget);
      expect(find.text('保存修改'), findsOneWidget);
    },
  );

  testWidgets('edit transaction bottom sheet keeps height while type changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = DatabaseService();
    final ledger = await _saveLedgerFixture(database);
    final transaction = _transactionFixture(ledger);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (context) => EditTransactionSheet(
                      transaction: transaction,
                      ledger: ledger,
                    ),
                  );
                },
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    final topBefore = tester.getTopLeft(find.text('编辑明细')).dy;

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    final topAfterIncome = tester.getTopLeft(find.text('编辑明细')).dy;

    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();
    final topAfterExpense = tester.getTopLeft(find.text('编辑明细')).dy;

    expect(topAfterIncome, moreOrLessEquals(topBefore));
    expect(topAfterExpense, moreOrLessEquals(topBefore));
  });
}

Future<Ledger> _saveLedgerFixture(DatabaseService database) async {
  final ledger = Ledger()
    ..uuid = 'ledger-1'
    ..name = '旅行账本'
    ..baseCurrencyCode = 'USD'
    ..exchangeRateToCNY = 7.2
    ..personUuids = ['person-1', 'person-2'];
  await database.saveLedger(ledger);
  await database.savePerson(
    Person()
      ..uuid = 'person-1'
      ..name = 'Simon'
      ..avatar = '😎',
  );
  await database.savePerson(
    Person()
      ..uuid = 'person-2'
      ..name = '朋友'
      ..avatar = '🙂',
  );
  return ledger;
}

TransactionRecord _transactionFixture(Ledger ledger) {
  return TransactionRecord()
    ..uuid = 'transaction-1'
    ..ledgerUuid = ledger.uuid
    ..type = 0
    ..amount = 12.34
    ..currencyCode = 'USD'
    ..category = '餐饮'
    ..personUuids = ['person-1']
    ..note = ''
    ..createdAt = DateTime(2026, 6, 1);
}
