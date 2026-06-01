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
              onShare: (_) {},
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
}
