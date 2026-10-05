import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/bookkeeping_tab.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/edit_transaction_sheet.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_form_components.dart';

Future<Ledger> fixture(DatabaseService database) async {
  final ledger = Ledger()
    ..uuid = 'ux-ledger'
    ..name = '家庭账本'
    ..baseCurrencyCode = 'CNY'
    ..personUuids = ['p1', 'p2'];
  await database.saveLedger(ledger);
  for (final id in ledger.personUuids) {
    await database.savePerson(
      Person()
        ..uuid = id
        ..name = id == 'p1' ? '小王' : '小李'
        ..avatar = '🙂',
    );
  }
  return ledger;
}

Future<void> mount(
  WidgetTester tester,
  DatabaseService database,
  Widget child,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        authTokenProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('changing UTC record day keeps the displayed local time', () {
    final original = DateTime.utc(2026, 6, 16, 23, 30, 45);
    final local = original.toLocal();
    final changed = transactionDateOnDay(DateTime(2026, 6, 15), original);
    expect(
      changed,
      DateTime(2026, 6, 15, local.hour, local.minute, local.second),
    );
    expect(changed.isUtc, isFalse);
  });
  testWidgets('field reveal jumps immediately when animations are disabled', (
    tester,
  ) async {
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 1000),
                  Text('待校验字段', key: anchor),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(anchor)).dy, greaterThan(600));
    revealTransactionField(anchor);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(anchor)).dy, lessThan(600));
  });
  testWidgets('pending save disables fields until profile loads', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    final profile = Completer<LocalProfile>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
          localProfileProvider.overrideWith((ref) => profile.future),
        ],
        child: MaterialApp(
          home: Scaffold(body: BookkeepingTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final amount = find.byKey(const ValueKey('bookkeeping-amount-input'));
    await tester.enterText(amount, '24');
    await tester.tap(find.text('保存记账'));
    await tester.pump();
    expect(tester.widget<TextField>(amount).enabled, isFalse);
    profile.complete(LocalProfile.defaultProfile);
    await tester.pumpAndSettle();
    expect(
      (await database.getTransactionsForLedger(ledger.uuid)).single.amount,
      24,
    );
    expect(tester.widget<TextField>(amount).enabled, isTrue);
  });
  testWidgets('closing while profile loads does not save or use disposed ref', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    final profile = Completer<LocalProfile>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
          localProfileProvider.overrideWith((ref) => profile.future),
        ],
        child: MaterialApp(
          home: Scaffold(body: BookkeepingTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      '24',
    );
    await tester.tap(find.text('保存记账'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    profile.complete(LocalProfile.defaultProfile);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(await database.getTransactionsForLedger(ledger.uuid), isEmpty);
  });
  testWidgets(
    'wide rail layout keeps save above keyboard with no nav reserve',
    (tester) async {
      final database = DatabaseService();
      final ledger = await fixture(database);
      await tester.binding.setSurfaceSize(const Size(1000, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(1000, 844),
                viewInsets: EdgeInsets.only(bottom: 300),
              ),
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                body: BookkeepingTab(
                  ledgers: [ledger],
                  bottomNavigationReserve: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('save-enabled'))).dy,
        lessThanOrEqualTo(544),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('shared date picker preserves time and forbids future days', (
    tester,
  ) async {
    DateTime? chosen;
    final existing = DateTime(2026, 6, 16, 14, 23, 45, 67, 89);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionDateControl(
            date: existing,
            onChanged: (value) => chosen = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transaction-calendar-toggle')));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(DateUtils.isSameDay(picker.lastDate, DateTime.now()), isTrue);
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(chosen, DateTime(2026, 6, 15, 14, 23, 45, 67, 89));
    expect(find.byType(TimePickerDialog), findsNothing);
  });
  testWidgets('transaction time shows hours and minutes and opens picker', (
    tester,
  ) async {
    DateTime? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionDateControl(
            date: DateTime(2026, 6, 16, 14, 23, 45, 67),
            onChanged: (value) => chosen = value,
          ),
        ),
      ),
    );
    expect(find.textContaining('14:23'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('transaction-hour-input')),
      '09',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-minute-input')),
      '07',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(chosen, DateTime(2026, 6, 16, 9, 7, 45, 67));
  });
  testWidgets(
    'manual past date is saved and date returns to today after success',
    (tester) async {
      final database = DatabaseService();
      final ledger = await fixture(database);
      await mount(tester, database, BookkeepingTab(ledgers: [ledger]));
      final date = DateTime(2026, 6, 15, 12, 34);
      tester
          .widget<TransactionDateControl>(find.byType(TransactionDateControl))
          .onChanged(date);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('bookkeeping-amount-input')),
        '24',
      );
      await tester.tap(find.text('保存记账'));
      await tester.pumpAndSettle();
      final records = await database.getTransactionsForLedger(ledger.uuid);
      expect(records.single.createdAt, date);
      expect(
        tester
            .widget<TransactionDateControl>(find.byType(TransactionDateControl))
            .date,
        isNull,
      );
    },
  );
  testWidgets('edit day changes without changing existing time', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    final record = TransactionRecord()
      ..uuid = 'edited'
      ..ledgerUuid = ledger.uuid
      ..type = 0
      ..amount = 30
      ..currencyCode = 'CNY'
      ..category = '餐饮'
      ..personUuids = ['p1']
      ..note = ''
      ..createdAt = DateTime(2026, 6, 16, 14, 23);
    await database.saveTransaction(record);
    await mount(
      tester,
      database,
      EditTransactionSheet(transaction: record, ledger: ledger),
    );
    final day = transactionDateOnDay(DateTime(2026, 6, 15), record.createdAt);
    tester
        .widget<TransactionDateControl>(find.byType(TransactionDateControl))
        .onChanged(day);
    await tester.pump();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(
      (await database.getTransactionsForLedger(ledger.uuid)).single.createdAt,
      DateTime(2026, 6, 15, 14, 23),
    );
  });
  testWidgets('deselecting participants keeps inline error until corrected', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    await mount(tester, database, BookkeepingTab(ledgers: [ledger]));
    await tester.enterText(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      '30',
    );
    await tester.ensureVisible(find.text('全选'));
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('取消全选'));
    await tester.tap(find.text('取消全选'));
    await tester.tap(find.text('保存记账'));
    await tester.pumpAndSettle();
    expect(find.text('请至少选择一个参与人员'), findsOneWidget);
    expect(await database.getTransactionsForLedger(ledger.uuid), isEmpty);
    await tester.ensureVisible(find.text('小王'));
    await tester.tap(find.text('小王'));
    await tester.pumpAndSettle();
    expect(find.text('请至少选择一个参与人员'), findsNothing);
    expect(find.textContaining('每人 CNY 30.00'), findsOneWidget);
  });
  testWidgets('split summary reacts to amount and income recipients', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    await mount(tester, database, BookkeepingTab(ledgers: [ledger]));
    await tester.enterText(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      '30',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('全选'));
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('共同钱包付款 · 2 人承担'), findsOneWidget);
    await tester.ensureVisible(find.text('收入'));
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('收入分配 · 2 人收款'), findsOneWidget);
  });
  testWidgets(
    'bookkeeping shows totals and per person amounts in both currencies',
    (tester) async {
      final database = DatabaseService();
      final ledger = await fixture(database);
      ledger.baseCurrencyCode = 'USD';
      ledger.exchangeRateToCNY = 7.2;
      await database.saveLedger(ledger);
      await mount(tester, database, BookkeepingTab(ledgers: [ledger]));
      await tester.tap(find.byKey(const ValueKey('currency-option-USD')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('bookkeeping-amount-input')),
        '100',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('全选'));
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('总额 USD 100.00'), findsOneWidget);
      expect(find.text('每人 USD 50.00'), findsOneWidget);
      expect(find.text('总额 ≈ CNY 720.00'), findsOneWidget);
      expect(find.text('每人 ≈ CNY 360.00'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('bookkeeping-amount-input')),
        '50',
      );
      await tester.pumpAndSettle();
      expect(find.text('总额 USD 50.00'), findsOneWidget);
      expect(find.text('每人 ≈ CNY 180.00'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('currency-option-CNY')),
      );
      await tester.tap(find.byKey(const ValueKey('currency-option-CNY')));
      await tester.pumpAndSettle();
      expect(find.text('总额 CNY 50.00'), findsOneWidget);
      expect(find.text('每人 ≈ USD 3.47'), findsOneWidget);
      await tester.ensureVisible(find.text('小李'));
      await tester.tap(find.text('小李'));
      await tester.pumpAndSettle();
      expect(find.text('每人 CNY 50.00'), findsOneWidget);
      expect(find.text('每人 ≈ USD 6.94'), findsOneWidget);
    },
  );

  testWidgets('empty state creates first ledger directly', (tester) async {
    var creates = 0;
    await mount(
      tester,
      DatabaseService(),
      BookkeepingTab(ledgers: const [], onCreateLedger: () => creates++),
    );
    await tester.tap(find.text('创建第一本账本'));
    expect(creates, 1);
  });
  testWidgets('recent list shows latest three and opens selected ledger', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = await fixture(database);
    for (var index = 1; index <= 4; index++) {
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'recent-$index'
          ..ledgerUuid = ledger.uuid
          ..type = 0
          ..amount = index.toDouble()
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..personUuids = ['p1']
          ..note = '记录$index'
          ..createdAt = DateTime(
            2026,
            6,
            index,
            index == 4 ? 13 : 0,
            index == 4 ? 7 : 0,
          ),
      );
    }
    Ledger? opened;
    await mount(
      tester,
      database,
      BookkeepingTab(
        ledgers: [ledger],
        onOpenLedger: (value) => opened = value,
      ),
    );
    expect(find.textContaining('记录1'), findsNothing);
    expect(find.textContaining('记录4'), findsOneWidget);
    expect(find.textContaining('6月4日 13:07 · 记录4'), findsOneWidget);
    await tester.ensureVisible(find.text('查看流水'));
    await tester.tap(find.text('查看流水'));
    expect(opened?.uuid, ledger.uuid);
  });
}
