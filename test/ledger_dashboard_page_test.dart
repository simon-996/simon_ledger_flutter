import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/utils/transaction_date.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/screens/ledger_dashboard_page.dart';

void main() {
  testWidgets('long ledger title stays centered between toolbar actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'title-ledger'
      ..name = '和朋友一起出行的旅行生活账本'
      ..baseCurrencyCode = 'CNY';
    await database.saveLedger(ledger);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LedgerDashboardPage(ledger: ledger),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text(ledger.name),
    );
    expect(tester.getCenter(title).dx, closeTo(195, 0.5));
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'day totals convert currency and custom drilldown includes late end date',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = DatabaseService();
      final ledger = Ledger()
        ..uuid = 'foreign-ledger'
        ..name = '外币账本'
        ..baseCurrencyCode = 'USD'
        ..exchangeRateToCNY = 7;
      await database.saveLedger(ledger);
      for (final (id, type, currency, amount, date) in [
        ('usd', 0, 'USD', 2.0, DateTime(2025, 1, 2, 23, 59)),
        ('cny', 0, 'CNY', 7.0, DateTime(2025, 1, 2, 10)),
        ('income', 1, 'USD', 5.0, DateTime(2025, 1, 2, 9)),
        ('outside', 0, 'USD', 9.0, DateTime(2025, 1, 3)),
      ]) {
        await database.saveTransaction(
          TransactionRecord()
            ..uuid = id
            ..ledgerUuid = ledger.uuid
            ..type = type
            ..amount = amount
            ..currencyCode = currency
            ..category = '餐饮'
            ..note = id
            ..createdAt = date,
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: LedgerDashboardPage(
              ledger: ledger,
              initialCategory: '餐饮',
              initialTransactionType: 0,
              initialDateRange: TransactionDateRange.custom(
                DateTime(2025, 1, 2),
                DateTime(2025, 1, 2),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2025年1月2日'), findsOneWidget);
      expect(find.text('支出 CNY 21.00 · 收入 CNY 0.00'), findsOneWidget);
      expect(find.text('支出 (CNY)'), findsOneWidget);
      expect(find.text('结余 (CNY)'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FittedBox).first,
          matching: find.text('CNY 21.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('outside'), findsNothing);
      expect(find.text('income'), findsNothing);
      expect(find.text('2025-01-02 23:59'), findsOneWidget);
      await tester.tap(find.text('US\$ USD').first);
      await tester.pumpAndSettle();
      expect(find.text('支出 USD 3.00 · 收入 USD 0.00'), findsOneWidget);
      expect(find.text('支出 (USD)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FittedBox).first,
          matching: find.text('USD 3.00'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('usd'));
      await tester.pumpAndSettle();
      expect(find.text('支出明细'), findsOneWidget);
      expect(find.byTooltip('编辑'), findsOneWidget);
    },
  );
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

    expect(
      tester.getTopLeft(find.byType(TextField)).dy,
      lessThan(tester.getTopLeft(find.text('结余 (CNY)')).dy),
    );
    expect(find.text('6月2日'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1000, 1100));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('人员结余')).dx, greaterThan(500));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();

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
    expect(find.text('收入 (CNY)'), findsOneWidget);
    expect(find.text('结余 (CNY)'), findsNothing);

    await tester.tap(find.byTooltip('筛选流水'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('支出').last);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(find.text('支出 (CNY)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FittedBox).first,
        matching: find.text('CNY 28.00'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '不存在的备注');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('无匹配流水'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '清除筛选').last);
    await tester.pumpAndSettle();
    expect(find.text('工资到账'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('结余 (CNY)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FittedBox).first,
        matching: find.text('CNY 1172.00'),
      ),
      findsOneWidget,
    );
  });
}
