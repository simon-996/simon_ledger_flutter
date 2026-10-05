import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/bookkeeping_tab.dart';
import 'transaction_ux_test.dart' show fixture, mount;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AppNotice.dismiss);

  testWidgets('saved notice stays at top and leaves save button usable', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    await mount(tester, database, BookkeepingTab(ledgers: [ledger]));
    await tester.enterText(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      '12.50',
    );
    await tester.tap(find.text('保存记账'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('支出已记下'), findsOneWidget);
    expect(find.textContaining('12.50'), findsWidgets);
    expect(
      tester.getBottomLeft(find.text('撤销')).dy,
      lessThan(tester.getTopLeft(find.text('保存记账')).dy),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('撤销'), findsOneWidget);
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(await database.getTransactionsForLedger(ledger.uuid), isEmpty);
  });

  testWidgets('continuous saves replace notice and undo latest transaction', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    await mount(tester, database, BookkeepingTab(ledgers: [ledger]));
    for (final amount in ['10', '20']) {
      await tester.enterText(
        find.byKey(const ValueKey('bookkeeping-amount-input')),
        amount,
      );
      await tester.tap(find.text('保存记账'));
      await tester.pumpAndSettle();
    }
    expect(find.text('撤销'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(
      (await database.getTransactionsForLedger(ledger.uuid)).single.amount,
      10,
    );
  });

  testWidgets('accessible actionable notice remains until dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AppNotice.success(
                  context,
                  '已保存',
                  actionLabel: '撤销',
                  onAction: () {},
                ),
                child: const Text('保存'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('撤销'), findsOneWidget);
  });
}
