import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/screens/ledger_dashboard_page.dart';

void main() {
  testWidgets('ledger dashboard filters transactions by search and type', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['person-1'];
    await database.saveLedger(ledger);
    await database.savePerson(
      Person()
        ..uuid = 'person-1'
        ..name = 'Simon'
        ..avatar = '😎',
    );
    await database.saveTransaction(
      TransactionRecord()
        ..uuid = 'expense-1'
        ..ledgerUuid = ledger.uuid
        ..type = 0
        ..amount = 28
        ..currencyCode = 'CNY'
        ..category = '餐饮'
        ..note = '咖啡'
        ..personUuids = ['person-1']
        ..createdAt = DateTime(2026, 6, 1, 9),
    );
    await database.saveTransaction(
      TransactionRecord()
        ..uuid = 'income-1'
        ..ledgerUuid = ledger.uuid
        ..type = 1
        ..amount = 1200
        ..currencyCode = 'CNY'
        ..category = '工资'
        ..note = '工资到账'
        ..personUuids = ['person-1']
        ..createdAt = DateTime(2026, 6, 2, 10),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(home: LedgerDashboardPage(ledger: ledger)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('咖啡'), findsOneWidget);
    expect(find.text('工资到账'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '咖啡');
    await tester.pumpAndSettle();

    expect(find.text('咖啡'), findsWidgets);
    expect(find.text('工资到账'), findsNothing);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选流水'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(find.text('工资到账'), findsOneWidget);
    expect(find.text('咖啡'), findsNothing);
  });
}
