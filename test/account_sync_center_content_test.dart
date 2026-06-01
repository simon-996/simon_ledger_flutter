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

    expect(find.text('正在同步'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('sync center exposes refresh and sync actions when idle', (
    tester,
  ) async {
    var refreshCalls = 0;
    var syncCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountSyncCenterContent(
            overview: overview,
            syncing: false,
            onRefresh: () => refreshCalls += 1,
            onSync: () => syncCalls += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('刷新同步状态'));
    await tester.tap(find.text('立即同步'));

    expect(refreshCalls, 1);
    expect(syncCalls, 1);
  });
}
