import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
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

    expect(_rateFieldFinder(), findsNothing);
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

    expect(_rateFieldFinder(), findsNothing);
    expect(find.text('人民币账本汇率固定为 1'), findsOneWidget);
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

    await tester.tap(find.text('CNY · 人民币'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD · 美元').last);
    await tester.pumpAndSettle();

    final rateField = tester.widget<TextField>(_rateFieldFinder());
    expect(rateField.enabled, isNot(false));
    expect(rateField.controller!.text, '1');
    await tester.enterText(_rateFieldFinder(), '7.2');
    await tester.pump();
    expect(find.text('1 USD = 7.2 CNY'), findsOneWidget);
    expect(find.text('1 CNY ≈ 0.138889 USD'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '账本名称',
      ),
      '外币账本',
    );
    await tester.enterText(_rateFieldFinder(), 'NaN');
    await tester.pump();
    await tester.tap(find.text('创建账本'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_rateFieldFinder()).decoration?.errorText,
      '请输入大于 0 的有效汇率',
    );
    expect(find.byType(CreateLedgerSheet), findsOneWidget);
  });

  testWidgets(
    'reverse rate entry saves normalized rate and switching preserves its meaning',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      CreateLedgerResult? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(DatabaseService()),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<CreateLedgerResult>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const CreateLedgerSheet(),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '账本名称',
        ),
        '反向汇率账本',
      );
      await tester.tap(find.text('CNY · 人民币'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD · 美元').last);
      await tester.pumpAndSettle();
      await tester.enterText(_rateFieldFinder(), '7.2');
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('rate-direction-inverse')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rate-direction-inverse')));
      await tester.pump();
      expect(
        double.parse(
          tester.widget<TextField>(_rateFieldFinder()).controller!.text,
        ),
        closeTo(1 / 7.2, 1e-12),
      );
      for (final invalid in ['', '0', '-1', 'NaN', 'Infinity', '1e-320']) {
        await tester.enterText(_rateFieldFinder(), invalid);
        await tester.pump();
        await tester.tap(find.text('创建账本'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(_rateFieldFinder()).decoration?.errorText,
          '请输入大于 0 的有效汇率',
        );
        expect(result, isNull);
      }
      await tester.enterText(_rateFieldFinder(), '0.125');
      await tester.pump();
      expect(find.text('1 CNY = 0.125 USD'), findsOneWidget);
      expect(find.text('1 USD = 8 CNY'), findsOneWidget);
      await tester.tap(find.text('创建账本'));
      await tester.pumpAndSettle();
      expect(result!.exchangeRateToCNY, 8);
      expect(result!.baseCurrencyCode, 'USD');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing rate handles direction and CNY reset at narrow large text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(280, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ledger = Ledger()
        ..uuid = 'edit-rate'
        ..name = '旅行账本'
        ..baseCurrencyCode = 'JPY'
        ..exchangeRateToCNY = 0.05;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(DatabaseService()),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(body: CreateLedgerSheet(existingLedger: ledger)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 JPY = 0.05 CNY'), findsOneWidget);
      final inverse = find.byKey(const ValueKey('rate-direction-inverse'));
      await tester.ensureVisible(inverse);
      await tester.pumpAndSettle();
      await tester.tap(inverse);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_rateFieldFinder()).controller!.text,
        '20',
      );
      expect(find.text('1 CNY = 20 JPY'), findsOneWidget);
      await tester.enterText(_rateFieldFinder(), '');
      await tester.pumpAndSettle();
      expect(find.text('1 CNY = 20 JPY'), findsNothing);
      await tester.enterText(_rateFieldFinder(), '0.125');
      await tester.pumpAndSettle();
      final currency = find.text('JPY · 日元');
      await tester.ensureVisible(currency);
      await tester.pumpAndSettle();
      await tester.tap(currency);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CNY · 人民币').last);
      await tester.pumpAndSettle();
      expect(_rateFieldFinder(), findsNothing);
      expect(inverse, findsNothing);
      expect(find.text('人民币账本汇率固定为 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
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

  testWidgets('local ledger creation uses the same default self profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    await database.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: CreateLedgerSheet())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('我'), findsOneWidget);
    expect(find.text('本人'), findsNothing);
  });

  testWidgets('local ledger creation links self person to local profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    await database.savePerson(
      Person()
        ..uuid = 'self'
        ..name = '本人'
        ..avatar = '😎',
    );
    CreateLedgerResult? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
          localProfileProvider.overrideWith(
            (ref) async =>
                const LocalProfile(nickname: 'Simon', avatarIcon: 'star'),
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

    expect(find.text('Simon'), findsOneWidget);
    expect(find.text('本人'), findsNothing);

    final ledgerNameField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '账本名称',
    );
    await tester.enterText(ledgerNameField, '本地账本');
    await tester.pump();
    await tester.tap(find.text('创建账本'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.personIds, contains('self'));
    expect(result!.people.single.uuid, 'self');
    expect(result!.people.single.name, 'Simon');
    expect(result!.people.single.avatar, '⭐');
    await database.savePerson(result!.people.single);
    final prefs = await SharedPreferences.getInstance();
    final storedPeople =
        jsonDecode(prefs.getString('local_store.guest.people.v2')!) as List;
    expect(storedPeople.single['isLocalSelf'], isTrue);
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

  testWidgets(
    'new ledger draft self matches default local profile while loading',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth_token_name': 'satoken',
        'auth_token_value': 'token',
        'auth_account_uuid': 'account-1',
      });
      final profileCompleter = Completer<LocalProfile>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authTokenProvider.overrideWith(
              (ref) async => const AuthToken(name: 'satoken', value: 'token'),
            ),
            currentUserProvider.overrideWith((ref) async => null),
            localProfileProvider.overrideWith((ref) => profileCompleter.future),
          ],
          child: const MaterialApp(home: Scaffold(body: CreateLedgerSheet())),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('我'), findsOneWidget);
      expect(find.text('本人'), findsNothing);
    },
  );

  testWidgets('new cloud ledger self person follows loaded account profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token_name': 'satoken',
      'auth_token_value': 'token',
      'auth_account_uuid': 'account-1',
    });
    CreateLedgerResult? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authTokenProvider.overrideWith(
            (ref) async => const AuthToken(name: 'satoken', value: 'token'),
          ),
          currentUserProvider.overrideWith(
            (ref) async => const AuthUser(
              uuid: 'account-1',
              nickname: '远端 Simon',
              avatar: '😎',
            ),
          ),
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

    expect(find.text('远端 Simon'), findsOneWidget);

    final ledgerNameField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '账本名称',
    );
    await tester.enterText(ledgerNameField, '家庭账本');
    await tester.pump();
    await tester.tap(find.text('创建账本'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.people.single.name, '远端 Simon');
    expect(result!.people.single.avatar, '😎');
    expect(result!.people.single.linkedUserUuid, 'account-1');
  });
}

Finder _rateFieldFinder() =>
    find.byKey(const ValueKey('ledger-exchange-rate-input'));
