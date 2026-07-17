import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/transaction_repository.dart';
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
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: BookkeepingTab(ledgers: [ledger]),
            bottomNavigationBar: const SizedBox(height: 70),
          ),
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

  testWidgets(
    'bookkeeping amount input autofocuses with a tight keyboard bar',
    (tester) async {
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
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                viewInsets: EdgeInsets.only(bottom: 300),
              ),
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                body: BookkeepingTab(ledgers: [ledger]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountInput = find.byKey(
        const ValueKey('bookkeeping-amount-input'),
      );
      expect(amountInput, findsOneWidget);
      expect(tester.widget<TextField>(amountInput).focusNode?.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      final mediaQuery = MediaQuery.of(
        tester.element(find.byType(BookkeepingTab)),
      );
      final keyboardTop = mediaQuery.size.height - mediaQuery.viewInsets.bottom;
      final saveButtonBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('save-enabled')))
          .dy;
      expect(keyboardTop - saveButtonBottom, lessThanOrEqualTo(24));
    },
  );

  testWidgets(
    'saving transaction keeps keyboard dismissed and success dialog visible',
    (tester) async {
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
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                viewInsets: EdgeInsets.only(bottom: 300),
              ),
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                body: BookkeepingTab(ledgers: [ledger]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountInput = find.byKey(
        const ValueKey('bookkeeping-amount-input'),
      );
      await tester.enterText(amountInput, '12.50');
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('保存记账'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('支出已记下'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.widget<TextField>(amountInput).autofocus, isFalse);

      final mediaQuery = MediaQuery.of(
        tester.element(find.byType(BookkeepingTab)),
      );
      final keyboardTop = mediaQuery.size.height - mediaQuery.viewInsets.bottom;
      final successCardBottom = tester
          .getBottomLeft(
            find.ancestor(of: find.text('支出已记下'), matching: find.byType(Card)),
          )
          .dy;
      expect(successCardBottom, lessThanOrEqualTo(keyboardTop - 16));

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'locally saved transaction still shows success after post-save failure',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = DatabaseService();
      final ledger = await _saveLedgerFixture(database);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            transactionRepositoryProvider.overrideWithValue(
              _PostSaveFailureTransactionRepository(database),
            ),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              resizeToAvoidBottomInset: false,
              body: BookkeepingTab(ledgers: [ledger]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('bookkeeping-amount-input')),
        '12.50',
      );
      await tester.tap(find.text('保存记账'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      final transactions = await database.getTransactionsForLedger(ledger.uuid);
      expect(transactions, hasLength(1));
      expect(find.text('支出已记下'), findsOneWidget);
      expect(find.textContaining('失败'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'saving without selected ledger highlights selector and shows notice',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = DatabaseService();
      final firstLedger = await _saveLedgerFixture(database);
      final secondLedger = Ledger()
        ..uuid = 'ledger-2'
        ..name = '家庭账本'
        ..baseCurrencyCode = 'CNY'
        ..personUuids = ['person-1'];
      await database.saveLedger(secondLedger);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BookkeepingTab(ledgers: [firstLedger, secondLedger]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('点击选择一个账本'), findsOneWidget);

      await tester.tap(find.text('保存记账'));
      await tester.pump();

      expect(find.text('请先选择一个所属账本'), findsOneWidget);

      final context = tester.element(find.byType(BookkeepingTab));
      final colorScheme = Theme.of(context).colorScheme;
      AppSectionCard headerCard() {
        final headerCards = find.ancestor(
          of: find.text('点击选择一个账本'),
          matching: find.byType(AppSectionCard),
        );
        return tester.widget<AppSectionCard>(headerCards.first);
      }

      expect(
        headerCard().borderColor,
        colorScheme.error.withValues(alpha: 0.72),
      );

      await tester.pump(const Duration(milliseconds: 800));

      expect(
        headerCard().borderColor,
        colorScheme.outlineVariant.withValues(alpha: 0.46),
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

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

class _PostSaveFailureTransactionRepository implements TransactionRepository {
  const _PostSaveFailureTransactionRepository(this._database);

  final DatabaseService _database;

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {
    await _database.saveTransaction(transaction);
    throw StateError('post-save refresh failed');
  }

  @override
  Future<List<TransactionRecord>> getCachedTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) {
    return _database.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) {
    return _database.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<List<TransactionRecord>> getTransactionsForLedgers(
    List<String> ledgerUuids, {
    bool includeDeleted = false,
  }) {
    return _database.getTransactionsForLedgers(
      ledgerUuids,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<void> deleteTransaction(String ledgerUuid, String uuid) {
    return _database.deleteTransaction(uuid);
  }

  @override
  Future<TransactionSyncResult> syncPendingTransactions(
    String ledgerUuid,
  ) async {
    return const TransactionSyncResult(synced: 0);
  }
}
