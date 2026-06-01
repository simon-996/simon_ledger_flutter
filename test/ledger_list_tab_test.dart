import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
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
              onDelete: (_) {},
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

    await tester.tap(find.byTooltip('同步待处理数据'));
    await tester.pump();

    expect(find.text('同步中'), findsOneWidget);
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

    expect(find.text('同步中'), findsNothing);
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
              onDelete: (_) {},
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
    expect(find.text('仅本地'), findsNothing);
    expect(find.text('等待上传'), findsNothing);
    expect(find.text('已同步至云端'), findsOneWidget);
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
              onDelete: (_) {},
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
}
