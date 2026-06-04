import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/auth_repository.dart';
import 'package:simon_ledger_flutter/core/services/sync_overview_service.dart';
import 'package:simon_ledger_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:simon_ledger_flutter/features/auth/presentation/widgets/account_tab.dart';

void main() {
  const overview = SyncOverview(
    ledgerPendingCount: 1,
    personPendingCount: 2,
    transactionPendingCount: 3,
    failedCount: 0,
    localOnlyLedgerCount: 1,
  );
  const failedOverview = SyncOverview(
    ledgerPendingCount: 0,
    personPendingCount: 0,
    transactionPendingCount: 1,
    failedCount: 1,
    localOnlyLedgerCount: 0,
    failures: [
      SyncFailureItem(
        type: SyncFailureType.transaction,
        title: '流水 · 餐饮',
        errorText: 'SocketException: offline',
      ),
    ],
  );
  const emptyOverview = SyncOverview(
    ledgerPendingCount: 0,
    personPendingCount: 0,
    transactionPendingCount: 0,
    failedCount: 0,
    localOnlyLedgerCount: 0,
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

  testWidgets('sync center keeps empty state visually quiet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountSyncCenterContent(
            overview: emptyOverview,
            syncing: false,
            onRefresh: () {},
            onSync: () {},
          ),
        ),
      ),
    );

    expect(find.text('本机没有待同步数据'), findsNothing);
    expect(find.text('暂无待同步'), findsOneWidget);
    expect(find.text('尚无成功同步记录'), findsOneWidget);
  });

  testWidgets('sync center shows friendly failure details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountSyncCenterContent(
            overview: failedOverview,
            syncing: false,
            onRefresh: () {},
            onSync: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看失败详情'));
    await tester.pumpAndSettle();

    expect(find.text('同步失败详情'), findsOneWidget);
    expect(find.text('流水 · 餐饮'), findsOneWidget);
    expect(find.text('网络恢复后会自动重试。'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets(
    'sync center ignores stale pending state when local queue is empty',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith(
              (ref) async => const AuthToken(name: 'satoken', value: 'token'),
            ),
            currentUserProvider.overrideWith((ref) async => null),
            syncOverviewProvider.overrideWith((ref) async => overview),
          ],
          child: const MaterialApp(home: Scaffold(body: AccountTab())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('立即同步'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('暂无需要同步的数据'), findsOneWidget);
      expect(find.text('同步完成'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('account profile card emphasizes nickname over account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith(
            (ref) async => const AuthToken(name: 'satoken', value: 'token'),
          ),
          currentUserProvider.overrideWith(
            (ref) async => const AuthUser(
              uuid: 'user-1',
              nickname: 'Simon',
              email: 'simon@example.com',
            ),
          ),
          localProfileProvider.overrideWith(
            (ref) async =>
                const LocalProfile(nickname: 'Simon', avatarIcon: 'person'),
          ),
          syncOverviewProvider.overrideWith((ref) async => emptyOverview),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountTab())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账户昵称和头像'), findsNothing);
    expect(find.text('修改'), findsNothing);
    expect(find.text('Simon'), findsOneWidget);
    expect(find.text('simon@example.com'), findsOneWidget);

    final nicknameStyle = tester.widget<Text>(find.text('Simon')).style;
    final accountStyle = tester
        .widget<Text>(find.text('simon@example.com'))
        .style;
    expect(nicknameStyle?.fontSize, greaterThan(accountStyle?.fontSize ?? 0));
    expect(
      nicknameStyle?.fontWeight?.value,
      greaterThan(FontWeight.w700.value),
    );
  });
}
