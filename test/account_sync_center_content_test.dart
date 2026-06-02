import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/services/sync_overview_service.dart';
import 'package:simon_ledger_flutter/features/auth/presentation/widgets/account_tab.dart';

void main() {
  const overview = SyncOverview(
    ledgerPendingCount: 1,
    personPendingCount: 2,
    transactionPendingCount: 3,
    failedCount: 0,
    localOnlyLedgerCount: 1,
  );

  testWidgets('sync center shows progress and disables actions while syncing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountSyncCenterContent(
            overview: overview,
            syncing: true,
            onRefresh: () {},
            onSync: () {},
          ),
        ),
      ),
    );

    expect(find.text('正在同步数据'), findsOneWidget);
    expect(find.text('同步中'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('刷新同步状态'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('sync center exposes refresh and sync actions when idle', (
    tester,
  ) async {
    var syncCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountSyncCenterContent(
            overview: overview,
            syncing: false,
            onRefresh: () {},
            onSync: () => syncCalls += 1,
          ),
        ),
      ),
    );

    expect(find.byTooltip('刷新同步状态'), findsNothing);
    await tester.tap(find.text('立即同步'));

    expect(syncCalls, 1);
  });
}
