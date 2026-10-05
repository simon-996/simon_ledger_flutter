import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_form_components.dart';

Future<void> mountDate(
  WidgetTester tester,
  DateTime? date,
  ValueChanged<DateTime> changed, {
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: TransactionDateControl(date: date, onChanged: changed),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('iOS time toggle restores the edited time shown by the wheel', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: TransactionDateControl(
            date: DateTime(2026, 6, 16, 14, 23),
            hasTime: true,
            onTimePrecisionChanged: (_) {},
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
    await tester.pumpAndSettle();
    tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .onDateTimeChanged(DateTime(2026, 6, 16, 9, 7));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    final shown = tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .initialDateTime;
    expect(shown.hour, 9);
    expect(shown.minute, 7);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 6, 16, 9, 7));
  });
  testWidgets('quick date updates an already expanded calendar selection', (
    tester,
  ) async {
    await mountDate(tester, DateTime(2026, 6, 16, 14, 23), (_) {});
    await tester.tap(find.byKey(const ValueKey('transaction-calendar-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('昨天'));
    await tester.pumpAndSettle();
    final yesterday = DateUtils.addDaysToDate(DateTime.now(), -1);
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(CalendarDatePicker)),
    );
    final selected = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(CalendarDatePicker),
            matching: find.byType(Semantics),
          ),
        )
        .where((widget) => widget.properties.selected == true);
    expect(
      selected.map((widget) => widget.properties.label),
      contains(contains(localizations.formatFullDate(yesterday))),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('iOS picker commits hours and minutes without changing date', (
    tester,
  ) async {
    DateTime? selected;
    final original = DateTime(2026, 6, 16, 14, 23, 45, 67);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: TransactionDateControl(
            date: original,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
    await tester.pumpAndSettle();
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    expect(picker.use24hFormat, isTrue);
    picker.onDateTimeChanged(DateTime(2026, 10, 5, 9, 7));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 6, 16, 9, 7, 45, 67));
  });
  testWidgets('quick day commits once and preserves original time precision', (
    tester,
  ) async {
    DateTime? chosen;
    var changes = 0;
    final existing = DateTime(2026, 6, 16, 14, 23, 45, 67, 89);
    await mountDate(tester, existing, (value) {
      chosen = value;
      changes++;
    });
    expect(find.text('昨天'), findsOneWidget);
    await tester.tap(find.text('昨天'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    final yesterday = DateUtils.addDaysToDate(DateTime.now(), -1);
    expect(chosen, transactionDateOnDay(yesterday, existing));
    expect(changes, 1);
  });

  testWidgets('canceling staged edits does not change original date', (
    tester,
  ) async {
    DateTime? chosen;
    await mountDate(
      tester,
      DateTime(2026, 6, 16, 14, 23),
      (value) => chosen = value,
    );
    expect(find.text('昨天'), findsOneWidget);
    await tester.tap(find.text('昨天'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
  });

  testWidgets('untouched new record keeps save-time now', (tester) async {
    DateTime? chosen;
    await mountDate(tester, null, (value) => chosen = value);
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
  });

  testWidgets('time fields use 24 hour input and preserve date and seconds', (
    tester,
  ) async {
    DateTime? chosen;
    final date = DateTime(2026, 6, 16, 14, 23, 45, 67);
    await mountDate(tester, date, (value) => chosen = value);
    expect(
      find.byKey(const ValueKey('transaction-hour-input')),
      findsOneWidget,
    );
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

  testWidgets('invalid time keeps picker open until corrected', (tester) async {
    DateTime? chosen;
    await mountDate(
      tester,
      DateTime(2026, 6, 16, 14, 23),
      (value) => chosen = value,
    );
    expect(
      find.byKey(const ValueKey('transaction-hour-input')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-hour-input')),
      '25',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    expect(find.text('小时需为 00–23'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('transaction-hour-input')),
      '22',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(chosen?.hour, 22);
  });

  testWidgets('desktop uses compact picker instead of bottom sheet', (
    tester,
  ) async {
    await mountDate(
      tester,
      DateTime(2026, 6, 16),
      (_) {},
      size: const Size(1100, 750),
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('完成'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('transaction-date-picker')))
          .width,
      lessThanOrEqualTo(440),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
