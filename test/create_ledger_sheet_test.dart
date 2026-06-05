import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/auth_repository.dart';
import 'package:simon_ledger_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/widgets/create_ledger_sheet.dart';

void main() {
  testWidgets('new CNY ledger keeps exchange rate fixed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(DatabaseService()),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: CreateLedgerSheet())),
      ),
    );
    await tester.pump();

    final rateField = tester.widget<TextField>(_rateFieldFinder());
    expect(rateField.enabled, isFalse);
    expect(rateField.controller!.text, '1');
    expect(find.text('人民币账本汇率固定为 1'), findsOneWidget);
  });

  testWidgets('editing CNY ledger normalizes and locks exchange rate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final ledger = Ledger()
      ..uuid = 'legacy-cny-ledger'
      ..name = '人民币账本'
      ..baseCurrencyCode = 'CNY'
      ..exchangeRateToCNY = 7.2;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(DatabaseService()),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(body: CreateLedgerSheet(existingLedger: ledger)),
        ),
      ),
    );
    await tester.pump();

    final rateField = tester.widget<TextField>(_rateFieldFinder());
    expect(rateField.enabled, isFalse);
    expect(rateField.controller!.text, '1');
  });

  testWidgets('foreign currency ledger allows editing exchange rate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(DatabaseService()),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: CreateLedgerSheet())),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('CNY 人民币'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD 美元').last);
    await tester.pumpAndSettle();

    final rateField = tester.widget<TextField>(_rateFieldFinder());
    expect(rateField.enabled, isTrue);
    expect(rateField.controller!.text, '1');
    expect(find.text('1 USD = ? CNY'), findsOneWidget);
  });

  testWidgets('editing ledger shows newly added person immediately', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'local-ledger'
      ..name = '本地账本'
      ..baseCurrencyCode = 'CNY';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(body: CreateLedgerSheet(existingLedger: ledger)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('新增人员'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final personNameField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '人员名称',
    );
    await tester.enterText(personNameField, '新成员');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('新成员'), findsOneWidget);
    final personTileFinder = find.byKey(
      const ValueKey('person-select-tile-新成员'),
    );
    expect(personTileFinder, findsOneWidget);
    final personTile = tester.widget<AnimatedContainer>(personTileFinder);
    final decoration = personTile.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
  });

  testWidgets('creating ledger does not wait for remote account profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token_name': 'satoken',
      'auth_token_value': 'token',
      'auth_account_uuid': 'account-1',
    });
    final userCompleter = Completer<AuthUser?>();
    CreateLedgerResult? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authTokenProvider.overrideWith(
            (ref) async => const AuthToken(name: 'satoken', value: 'token'),
          ),
          currentUserProvider.overrideWith((ref) => userCompleter.future),
          localProfileProvider.overrideWith(
            (ref) async => LocalProfile.defaultProfile,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showModalBottomSheet<CreateLedgerResult>(
                    context: context,
                    builder: (context) => const CreateLedgerSheet(),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final ledgerNameField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '账本名称',
    );
    await tester.enterText(ledgerNameField, '离线创建');
    await tester.pump();
    await tester.tap(find.text('创建账本'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(result, isNotNull);
    expect(result!.people.single.linkedUserUuid, 'account-1');
    expect(userCompleter.isCompleted, isFalse);
  });
}

Finder _rateFieldFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == '对人民币汇率',
  );
}
