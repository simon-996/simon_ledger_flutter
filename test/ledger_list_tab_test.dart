import 'dart:async';

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
import 'package:simon_ledger_flutter/features/ledgers/presentation/widgets/ledger_list_tab.dart';

void main() {
  testWidgets('ledger sync button shows progress and blocks repeated taps', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'local-ledger'
      ..name = '待同步账本'
      ..baseCurrencyCode = 'CNY'
      ..cloudPolicy = LedgerCloudPolicy.uploadRequested
      ..pendingSync = true;
    await database.saveLedger(ledger);
    final releaseSync = Completer<void>();
    var syncCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith(
            (ref) async => const AuthToken(name: 'satoken', value: 'token'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LedgerListTab(
              ledgers: [ledger],
              ledgerStats: const {},
              onTap: (_) {},
              onEdit: (_) {},
              onShare: (_) async {},
              onDelete: (_) async {},
              onCreate: () {},
              onSync: (_) async {
                syncCalls += 1;
                await releaseSync.future;
              },
              autoSyncEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final syncButtonFinder = find.byTooltip('同步待处理数据');
    expect(
      tester.getTopLeft(syncButtonFinder).dx,
      lessThan(tester.getTopLeft(find.byTooltip('编辑')).dx),
    );

    await tester.tap(syncButtonFinder);
    await tester.pump();

    expect(find.text('正在同步账本'), findsOneWidget);
    expect(find.text('同步中'), findsNothing);
    expect(find.byTooltip('正在同步'), findsOneWidget);
    final syncingButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '正在同步',
      ),
    );
    expect(syncingButton.onPressed, isNull);
    expect(syncCalls, 1);

    releaseSync.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('正在同步账本'), findsNothing);
    expect(find.byTooltip('同步待处理数据'), findsOneWidget);
  });

  testWidgets('synced local ledger matches cloud card and exposes sharing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'local-ledger'
      ..syncedRemoteUuid = '0123456789abcdef0123456789abcdef'
      ..name = '已同步账本'
      ..baseCurrencyCode = 'CNY'
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged
      ..role = 'owner';
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
          home: Scaffold(
            body: LedgerListTab(
              ledgers: [ledger],
              ledgerStats: const {},
              onTap: (_) {},
              onEdit: (_) {},
              onShare: (_) async {},
              onDelete: (_) async {},
              onCreate: () {},
              onSync: (_) async {},
              autoSyncEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('分享邀请'), findsOneWidget);
    expect(find.text('本地已同步'), findsNothing);
    expect(find.text('本机'), findsNothing);
    expect(find.text('待同步'), findsNothing);
    expect(find.text('已同步'), findsOneWidget);
  });

  testWidgets('ledger share action animates card and blocks repeated taps', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'remote-ledger'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged
      ..role = 'owner';
    await database.saveLedger(ledger);
    final releaseShare = Completer<void>();
    var shareCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith(
            (ref) async => const AuthToken(name: 'satoken', value: 'token'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LedgerListTab(
              ledgers: [ledger],
              ledgerStats: const {},
              onTap: (_) {},
              onEdit: (_) {},
              onShare: (_) async {
                shareCalls += 1;
                await releaseShare.future;
              },
              onDelete: (_) async {},
              onCreate: () {},
              onSync: (_) async {},
              autoSyncEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('分享邀请'));
    await tester.pump();

    expect(find.text('正在生成邀请'), findsOneWidget);
    expect(shareCalls, 1);
    final sharingButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '分享邀请',
      ),
    );
    expect(sharingButton.onPressed, isNull);

    releaseShare.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('正在生成邀请'), findsNothing);
  });

  testWidgets(
    'ledger card shows one compact people list without group labels',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      final manualPerson = Person()
        ..uuid = 'manual-person'
        ..name = '小李'
        ..avatar = '🙂';
      final ledger = Ledger()
        ..uuid = 'local-ledger'
        ..name = '家庭账本'
        ..baseCurrencyCode = 'CNY'
        ..personUuids = [manualPerson.uuid]
        ..members = [
          LedgerMemberSummary(
            uuid: 'shared-person',
            nickname: '小王',
            avatar: '😀',
            role: 'editor',
          ),
        ]
        ..memberCount = 2;
      await database.savePerson(manualPerson);
      await database.saveLedger(ledger);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            home: Scaffold(
              body: LedgerListTab(
                ledgers: [ledger],
                ledgerStats: const {},
                onTap: (_) {},
                onEdit: (_) {},
                onShare: (_) async {},
                onDelete: (_) async {},
                onCreate: () {},
                onSync: (_) async {},
                autoSyncEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('小王'), findsOneWidget);
      expect(find.text('小李'), findsOneWidget);
      expect(find.text('共享成员'), findsNothing);
      expect(find.text('账本人员'), findsNothing);
      expect(find.byTooltip('小王 · 可记账 · 共享成员'), findsOneWidget);
      final sharedOffset = tester.getTopLeft(find.text('小王'));
      final manualOffset = tester.getTopLeft(find.text('小李'));
      final sharedBeforeManual =
          sharedOffset.dy < manualOffset.dy ||
          (sharedOffset.dy == manualOffset.dy &&
              sharedOffset.dx < manualOffset.dx);
      expect(sharedBeforeManual, isTrue);
    },
  );

  testWidgets(
    'ledger delete sheet shows details and waits for local deletion',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = DatabaseService();
      final ledger = Ledger()
        ..uuid = 'trip-ledger'
        ..name = '旅行账本'
        ..baseCurrencyCode = 'CNY';
      await database.saveLedger(ledger);
      for (var index = 0; index < 2; index += 1) {
        await database.saveTransaction(
          TransactionRecord()
            ..uuid = 'tx-$index'
            ..ledgerUuid = ledger.uuid
            ..amount = 20
            ..currencyCode = 'CNY'
            ..category = '餐饮'
            ..note = ''
            ..createdAt = DateTime(2026, 6, index + 1),
        );
      }
      final releaseDelete = Completer<void>();
      var deleteCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LedgerListTab(
                ledgers: [ledger],
                ledgerStats: const {},
                onTap: (_) {},
                onEdit: (_) {},
                onShare: (_) async {},
                onDelete: (_) async {
                  deleteCalls += 1;
                  await releaseDelete.future;
                },
                onCreate: () {},
                onSync: (_) async {},
                autoSyncEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.text('旅行账本'), const Offset(-420, 0));
      await tester.pumpAndSettle();

      expect(find.text('删除账本'), findsOneWidget);
      expect(find.text('旅行账本'), findsWidgets);
      expect(find.text(ledger.displayCode), findsWidgets);
      expect(find.text('本机账本'), findsOneWidget);
      expect(find.text('该账本包含 2 条流水，删除后无法恢复。'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pump();

      expect(find.text('正在删除'), findsOneWidget);
      expect(deleteCalls, 1);

      releaseDelete.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('账本已删除'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
