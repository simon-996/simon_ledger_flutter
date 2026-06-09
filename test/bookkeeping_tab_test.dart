import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/bookkeeping_tab.dart';

void main() {
  testWidgets('bookkeeping header keeps ledger selector visually quiet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = DatabaseService();
    final ledger = await _saveLedgerFixture(database);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(body: BookkeepingTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('旅行账本'), findsOneWidget);
    expect(find.textContaining(ledger.displayCode), findsOneWidget);

    final context = tester.element(find.byType(BookkeepingTab));
    final colorScheme = Theme.of(context).colorScheme;
    final headerCards = find.ancestor(
      of: find.text('旅行账本'),
      matching: find.byType(AppSectionCard),
    );
    final headerCard = tester.widget<AppSectionCard>(headerCards.first);

    expect(
      headerCard.color,
      colorScheme.surfaceContainerLow.withValues(alpha: 0.46),
    );
    expect(
      headerCard.borderColor,
      colorScheme.outlineVariant.withValues(alpha: 0.46),
    );
  });

  testWidgets('bookkeeping page accent follows transaction type', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = DatabaseService();
    final ledger = await _saveLedgerFixture(database);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(body: BookkeepingTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.receipt_long_outlined)).color,
      AppTheme.expenseColor,
    );
    expect(_saveButtonScheme(tester).primary, AppTheme.expenseColor);

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Icon>(find.byIcon(Icons.savings_outlined)).color,
      AppTheme.incomeColor,
    );
    expect(_saveButtonScheme(tester).primary, AppTheme.incomeColor);
  });

  testWidgets('bookkeeping amount controls use an Apple input panel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = DatabaseService();
    final ledger = await _saveLedgerFixture(database);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(body: BookkeepingTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(BookkeepingTab));
    final colorScheme = Theme.of(context).colorScheme;
    final panel = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('bookkeeping-amount-panel')),
    );
    final decoration = panel.decoration as BoxDecoration;
    final borderRadius = decoration.borderRadius! as BorderRadius;
    final border = decoration.border! as Border;

    expect(decoration.color, colorScheme.surfaceContainerLowest);
    expect(borderRadius.topLeft.x, 28);
    expect(border.top.color, colorScheme.outlineVariant.withValues(alpha: 0.7));
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('viewer ledgers are hidden from bookkeeping flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = '0123456789abcdef0123456789abcdef'
      ..name = '只读共享账本'
      ..baseCurrencyCode = 'CNY'
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged
      ..role = 'viewer'
      ..memberCount = 2;
    await database.saveLedger(ledger);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith(
            (ref) async => const AuthToken(name: 'satoken', value: 'token'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: BookkeepingTab(ledgers: [ledger])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前没有可记账的账本'), findsOneWidget);
    expect(find.text('只读共享账本'), findsNothing);
    expect(find.text('保存记账'), findsNothing);
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

ColorScheme _saveButtonScheme(WidgetTester tester) {
  final saveButtonContext = tester.element(find.text('保存记账'));
  return Theme.of(saveButtonContext).colorScheme;
}
