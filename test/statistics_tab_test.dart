import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/statistics/presentation/widgets/statistics_tab.dart';
import 'package:simon_ledger_flutter/features/statistics/presentation/widgets/statistics_date_preference.dart';

void main() {
  testWidgets(
    'daily trend ends today and default headers hide internal codes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      final now = DateTime.now();
      final ledger = Ledger()
        ..uuid = 'trend-ledger'
        ..name = '趋势账本'
        ..baseCurrencyCode = 'CNY';
      await database.saveLedger(ledger);
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'today-record'
          ..ledgerUuid = ledger.uuid
          ..category = '餐饮'
          ..note = '今天'
          ..type = 0
          ..amount = 20
          ..currencyCode = 'CNY'
          ..createdAt = now,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: StatisticsTab(ledgers: [ledger])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.spots.length, now.day);
      expect(
        chart.data.lineBarsData.single.spots.last.x,
        (now.day - 1).toDouble(),
      );
      expect(find.text(ledger.displayCode), findsNothing);
    },
  );
  testWidgets('replacing the selected ledger restores its own calendar month', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final first = Ledger()
      ..uuid = 'first-calendar'
      ..name = '账本一'
      ..baseCurrencyCode = 'CNY';
    final second = Ledger()
      ..uuid = 'second-calendar'
      ..name = '账本二'
      ..baseCurrencyCode = 'CNY';
    await database.saveLedger(first);
    await database.saveLedger(second);
    await StatisticsDatePreference(
      month: DateTime(2024, 2),
      mode: 'month',
    ).write(first.uuid);
    await StatisticsDatePreference(
      month: DateTime(2025, 7),
      mode: 'month',
    ).write(second.uuid);
    Widget app(List<Ledger> ledgers) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        authTokenProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: Scaffold(body: StatisticsTab(ledgers: ledgers)),
      ),
    );
    await tester.pumpWidget(app([first, second]));
    await tester.pumpAndSettle();
    expect(find.text('2024年2月'), findsOneWidget);
    await tester.pumpWidget(app([second]));
    await tester.pumpAndSettle();
    expect(find.text('2025年7月'), findsOneWidget);
    expect(find.text('2024年2月'), findsNothing);
  });
  testWidgets(
    'calendar browsing and category drilldown preserve statistics context',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = DatabaseService();
      final now = DateTime.now();
      final ledger = Ledger()
        ..uuid = 'drilldown-ledger'
        ..name = '分类账本'
        ..baseCurrencyCode = 'CNY';
      await database.saveLedger(ledger);
      for (final (id, category, monthOffset) in [
        ('a', '餐饮', -1),
        ('b', '交通', -1),
        ('c', '餐饮', 0),
      ]) {
        await database.saveTransaction(
          TransactionRecord()
            ..uuid = id
            ..ledgerUuid = ledger.uuid
            ..amount = 20
            ..type = 0
            ..currencyCode = 'CNY'
            ..category = category
            ..note = '记录$id'
            ..createdAt = DateTime(now.year, now.month + monthOffset, 5),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: StatisticsTab(ledgers: [ledger])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('上个月'));
      await tester.pumpAndSettle();
      final previous = DateTime(now.year, now.month - 1);
      expect(find.text('${previous.year}年${previous.month}月'), findsOneWidget);
      expect(find.textContaining('无上期记录'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('statistics-category-餐饮')),
      );
      await tester.tap(find.byKey(const ValueKey('statistics-category-餐饮')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('筛选流水'), findsOneWidget);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.text('记录a'), findsOneWidget);
      expect(find.text('记录b'), findsNothing);
      expect(find.text('记录c'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('${previous.year}年${previous.month}月'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('statistics-summary-card')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'statistics filters stay complete before a ledger preference loads',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = DatabaseService();
      final ledger = Ledger()
        ..uuid = 'stats-ledger'
        ..name = '旅行账本'
        ..baseCurrencyCode = 'CNY';
      await database.saveLedger(ledger);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: StatisticsTab(ledgers: [ledger])),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('正在准备统计'), findsNothing);
      expect(find.text('旅行账本'), findsOneWidget);
      expect(find.text('收支类型'), findsOneWidget);
      expect(find.text('时间范围'), findsOneWidget);
      expect(find.text('近7天'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('本年'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      final timeFilterTop = tester.getTopLeft(find.text('近7天')).dy;
      expect(
        tester.getTopLeft(find.text('本月')).dy,
        moreOrLessEquals(timeFilterTop),
      );
      expect(
        tester.getTopLeft(find.text('本年')).dy,
        moreOrLessEquals(timeFilterTop),
      );
      expect(
        tester.getTopLeft(find.text('全部')).dy,
        moreOrLessEquals(timeFilterTop),
      );
    },
  );

  testWidgets('statistics summary uses a white Apple surface', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'stats-ledger'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY';
    await database.saveLedger(ledger);
    await database.saveTransaction(
      TransactionRecord()
        ..uuid = 'stats-tx'
        ..ledgerUuid = ledger.uuid
        ..type = 0
        ..amount = 28
        ..currencyCode = 'CNY'
        ..category = '餐饮'
        ..note = ''
        ..createdAt = DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: StatisticsTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final context = tester.element(find.byType(StatisticsTab));
    final colorScheme = Theme.of(context).colorScheme;
    final summaryCard = tester.widget<AppSectionCard>(
      find.byKey(const ValueKey('statistics-summary-card')),
    );

    expect(summaryCard.color, colorScheme.surfaceContainerLowest);
    expect(
      summaryCard.borderColor,
      colorScheme.outlineVariant.withValues(alpha: 0.68),
    );
  });

  testWidgets('statistics summary follows bookkeeping transaction colors', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'stats-ledger'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY';
    await database.saveLedger(ledger);
    await database.saveTransaction(
      TransactionRecord()
        ..uuid = 'expense-tx'
        ..ledgerUuid = ledger.uuid
        ..type = 0
        ..amount = 28
        ..currencyCode = 'CNY'
        ..category = '餐饮'
        ..note = ''
        ..createdAt = DateTime.now(),
    );
    await database.saveTransaction(
      TransactionRecord()
        ..uuid = 'income-tx'
        ..ledgerUuid = ledger.uuid
        ..type = 1
        ..amount = 100
        ..currencyCode = 'CNY'
        ..category = '工资'
        ..note = ''
        ..createdAt = DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: StatisticsTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester
          .widget<Icon>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('statistics-summary-card')),
                  matching: find.byIcon(Icons.trending_down_rounded),
                )
                .first,
          )
          .color,
      AppColors.light.expense,
    );

    await tester.tap(find.text('收入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester
          .widget<Icon>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('statistics-summary-card')),
                  matching: find.byIcon(Icons.trending_up_rounded),
                )
                .first,
          )
          .color,
      AppColors.light.income,
    );
  });
}
