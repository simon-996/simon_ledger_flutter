import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/features/home/presentation/screens/home_page.dart';

void main() {
  testWidgets('ledger statistics and account tabs do not show top titles', (
    tester,
  ) async {
    for (final index in [1, 2, 3]) {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-$index'
          ..name = '旅行账本'
          ..baseCurrencyCode = 'CNY',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(home: HomePage(initialIndex: index)),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
    }
  });

  testWidgets(
    'switching from account to non-bookkeeping tabs keeps keyboard hidden',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-keyboard'
          ..name = '旅行账本'
          ..baseCurrencyCode = 'CNY',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: HomePage(initialIndex: 3)),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.text('账本'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('bookkeeping-amount-input')),
        findsOneWidget,
      );
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  testWidgets('account keyboard hides bottom navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authTokenProvider.overrideWith((ref) async => null)],
        child: const MaterialApp(home: HomePage(initialIndex: 3)),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-navigation-bar')), findsNothing);
  });

  testWidgets('home shows a compact conflict notice that opens the center', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final record = ConflictRecord(
      id: 'profile-conflict',
      accountUuid: 'account-a',
      entityType: ConflictEntityType.profile,
      ledgerUuid: null,
      localUuid: 'profile-local',
      remoteUuid: 'profile-remote',
      operation: ConflictOperation.update,
      baseVersion: 1,
      remoteVersion: 2,
      localSnapshot: const {'nickname': '本地昵称'},
      remoteSnapshot: const {'nickname': '云端昵称'},
      remoteDeleted: false,
      detectedAt: DateTime.utc(2026, 8, 30),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
          conflictRecordsProvider.overrideWith((ref) async => [record]),
          conflictLedgerNamesProvider.overrideWith((ref) async => const {}),
        ],
        child: const MaterialApp(home: HomePage(initialIndex: 3)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('有 1 项数据需要确认'), findsOneWidget);
    await tester.tap(find.text('有 1 项数据需要确认'));
    await tester.pumpAndSettle();

    expect(find.text('数据冲突'), findsOneWidget);
    expect(find.text('账户资料'), findsWidgets);
  });
}
