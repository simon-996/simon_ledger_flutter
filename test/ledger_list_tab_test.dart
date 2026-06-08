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

  testWidgets('ledger list filters cached ledgers locally by name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final travelLedger = Ledger()
      ..uuid = 'travel-ledger'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY';
    final homeLedger = Ledger()
      ..uuid = 'home-ledger'
      ..name = '家庭账本'
      ..baseCurrencyCode = 'CNY';
    await database.saveLedger(travelLedger);
    await database.saveLedger(homeLedger);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          home: Scaffold(
            body: LedgerListTab(
              ledgers: [travelLedger, homeLedger],
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

    expect(find.text('搜索账本'), findsOneWidget);
    expect(find.text('旅行账本'), findsOneWidget);
    expect(find.text('家庭账本'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '旅行');
    await tester.pump();

    expect(find.text('旅行账本'), findsOneWidget);
    expect(find.text('家庭账本'), findsNothing);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byTooltip('排序'), findsNothing);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pump();

    expect(find.text('没有找到匹配账本'), findsOneWidget);
    expect(find.text('清除搜索'), findsOneWidget);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('旅行账本'), findsOneWidget);
    expect(find.text('家庭账本'), findsOneWidget);
  });

  testWidgets('ledger search field uses an Apple rounded search surface', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'search-ledger'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY';
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

    final context = tester.element(find.byType(LedgerListTab));
    final colorScheme = Theme.of(context).colorScheme;
    final searchBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('ledger-search-surface')),
    );
    final decoration = searchBox.decoration as BoxDecoration;
    final borderRadius = decoration.borderRadius! as BorderRadius;
    final border = decoration.border! as Border;

    expect(decoration.color, colorScheme.surfaceContainerLow);
    expect(borderRadius.topLeft.x, 22);
    expect(
      border.top.color,
      colorScheme.outlineVariant.withValues(alpha: 0.62),
    );
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('ledger card uses an Apple floating surface', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'apple-ledger'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY';
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

    final context = tester.element(find.byType(LedgerListTab));
    final colorScheme = Theme.of(context).colorScheme;
    final card = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('ledger-card-surface-apple-ledger')),
    );
    final decoration = card.decoration! as BoxDecoration;
    final borderRadius = decoration.borderRadius! as BorderRadius;
    final border = decoration.border! as Border;

    expect(decoration.color, colorScheme.surfaceContainerLowest);
    expect(borderRadius.topLeft.x, 28);
    expect(
      border.top.color,
      colorScheme.outlineVariant.withValues(alpha: 0.68),
    );
    expect(decoration.boxShadow, isNotEmpty);
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

  testWidgets('ledger card prefers local linked user profile display', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    final selfPerson = Person()
      ..uuid = 'self'
      ..name = '新昵称'
      ..avatar = '⭐'
      ..linkedUserUuid = 'user-1';
    final ledger = Ledger()
      ..uuid = 'remote-ledger'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..members = [
        LedgerMemberSummary(
          uuid: 'member-self',
          userUuid: 'user-1',
          nickname: '旧昵称',
          avatar: '🙂',
          role: 'owner',
        ),
      ]
      ..memberCount = 1;
    await database.savePerson(selfPerson);
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

    expect(find.text('新昵称'), findsOneWidget);
    expect(find.text('旧昵称'), findsNothing);
    expect(find.byTooltip('新昵称 · 所有者 · 共享成员'), findsOneWidget);
  });

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

  testWidgets('shared non-owner ledger uses leave wording', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = '0123456789abcdef0123456789abcdef'
      ..name = '共享旅行'
      ..baseCurrencyCode = 'CNY'
      ..role = 'editor'
      ..memberCount = 2;
    await database.saveLedger(ledger);
    await database.saveTransaction(
      TransactionRecord()
        ..uuid = 'shared-tx'
        ..ledgerUuid = ledger.uuid
        ..amount = 20
        ..currencyCode = 'CNY'
        ..category = '餐饮'
        ..note = ''
        ..createdAt = DateTime(2026, 6, 1),
    );
    final releaseDelete = Completer<void>();

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
              onDelete: (_) => releaseDelete.future,
              onCreate: () {},
              onSync: (_) async {},
              autoSyncEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('共享旅行'), const Offset(-420, 0));
    await tester.pumpAndSettle();

    expect(find.text('退出账本'), findsOneWidget);
    expect(find.text('仅从你的列表移除'), findsOneWidget);
    expect(find.text('共享账本'), findsOneWidget);
    expect(find.text('该账本包含 1 条流水，退出后仅从你的列表移除，不会删除共享账本数据。'), findsOneWidget);
    expect(find.text('删除账本'), findsNothing);

    await tester.tap(find.text('退出'));
    await tester.pump();

    expect(find.text('正在退出'), findsOneWidget);
    expect(find.text('正在退出账本'), findsOneWidget);

    releaseDelete.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已退出账本，将同步到云端'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('wide ledger delete dialog keeps title away from top edge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'wide-ledger'
      ..name = '宽屏账本'
      ..baseCurrencyCode = 'CNY';
    await database.saveLedger(ledger);

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
              onDelete: (_) async {},
              onCreate: () {},
              onSync: (_) async {},
              autoSyncEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('宽屏账本'), const Offset(-420, 0));
    await tester.pumpAndSettle();

    final dialogTop = tester.getTopLeft(find.byType(Dialog)).dy;
    final titleTop = tester.getTopLeft(find.text('删除账本')).dy;
    expect(titleTop - dialogTop, greaterThanOrEqualTo(20));
  });
}
