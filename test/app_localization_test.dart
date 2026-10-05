import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/app.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/preferences/onboarding_preference.dart';

void main() {
  testWidgets('Chinese app uses Chinese calendar actions and range controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      OnboardingPreference.completedKey: true,
    });
    final database = DatabaseService();
    await database.saveLedger(
      Ledger()
        ..uuid = 'locale-ledger'
        ..name = '日常账本'
        ..baseCurrencyCode = 'CNY',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: const SimonLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();
    final date = find.byKey(const ValueKey('transaction-date-control'));
    await tester.ensureVisible(date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transaction-calendar-toggle')));
    await tester.pumpAndSettle();
    final calendarContext = tester.element(find.byType(CalendarDatePicker));
    expect(Localizations.localeOf(calendarContext).languageCode, 'zh');
    expect(find.text('SELECT DATE'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义日期'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    final labels = MaterialLocalizations.of(
      tester.element(find.byType(DateRangePickerDialog)),
    );
    expect(labels.cancelButtonLabel, '取消');
    expect(labels.dateRangeStartLabel, '开始日期');
    expect(labels.dateRangeEndLabel, '结束日期');
    expect(labels.closeButtonTooltip, '关闭');
    expect(tester.takeException(), isNull);
  });
}
