import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/services/conflict_coordinator.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/conflicts/presentation/screens/conflict_detail_page.dart';

void main() {
  tearDown(AppNotice.dismiss);

  testWidgets('detail emphasizes changed fields and collapses identical ones', (
    tester,
  ) async {
    await tester.pumpWidget(
      _scope(
        MaterialApp(home: ConflictDetailPage(record: _transactionRecord())),
      ),
    );

    expect(find.text('本机版本'), findsWidgets);
    expect(find.text('云端版本'), findsWidgets);
    expect(find.text('金额'), findsOneWidget);
    expect(find.text('备注'), findsNothing);
    expect(find.widgetWithText(FilledButton, '保留本机版本'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '使用云端版本'), findsOneWidget);

    await tester.tap(find.textContaining('查看相同字段'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('备注'), 200);

    expect(find.text('备注'), findsOneWidget);
  });

  testWidgets('person relations show names instead of raw UUIDs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConflictDetailContent(
            record: _transactionRecord(
              remoteSnapshot: const {
                'type': 0,
                'amount': 25,
                'currencyCode': 'CNY',
                'category': '餐饮',
                'happenedAt': '2026-08-30T08:00:00.000',
                'payerPersonUuid': 'person-2',
                'personUuids': ['person-2'],
                'note': '早餐',
              },
            ),
            identityLabels: const {'person-1': '🐱 小明'},
            showIdentical: true,
            onToggleIdentical: () {},
          ),
        ),
      ),
    );

    expect(find.text('🐱 小明'), findsWidgets);
    expect(find.text('参与人信息不可用'), findsWidgets);
    expect(find.textContaining('person-1'), findsNothing);
    expect(find.textContaining('person-2'), findsNothing);
  });

  testWidgets('destructive choices use explicit confirmation labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _scope(
        MaterialApp(
          home: ConflictDetailPage(
            record: _transactionRecord(operation: ConflictOperation.delete),
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '保留本机版本'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '确认删除'), findsOneWidget);
    expect(find.text('确定'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _scope(
        MaterialApp(
          home: ConflictDetailPage(
            record: _transactionRecord(remoteDeleted: true),
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '保留本机版本'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '覆盖云端并恢复'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '使用云端版本'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '使用云端删除结果'), findsOneWidget);
  });

  testWidgets('queued local choice closes detail and records the decision', (
    tester,
  ) async {
    var keepCalls = 0;
    await _pumpLauncher(
      tester,
      ConflictDetailPage(
        record: _transactionRecord(),
        keepLocal: (id) async {
          keepCalls += 1;
          return ConflictResolutionOutcome.queued;
        },
        loadNext: () async => null,
      ),
    );

    await tester.tap(find.text('打开冲突'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保留本机版本'));
    await tester.pumpAndSettle();

    expect(keepCalls, 1);
    expect(find.text('冲突已关闭'), findsOneWidget);
    AppNotice.dismiss();
    await tester.pump();
  });

  testWidgets('resolved choice opens the next conflict before closing', (
    tester,
  ) async {
    final handled = <String>[];
    var nextLoadCount = 0;
    await _pumpLauncher(
      tester,
      ConflictDetailPage(
        record: _transactionRecord(),
        keepLocal: (id) async {
          handled.add(id);
          return ConflictResolutionOutcome.resolved;
        },
        loadNext: () async {
          nextLoadCount += 1;
          return nextLoadCount == 1
              ? _transactionRecord(id: 'second-conflict', localAmount: 88)
              : null;
        },
      ),
    );

    await tester.tap(find.text('打开冲突'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保留本机版本'));
    await tester.pumpAndSettle();

    expect(find.byType(ConflictDetailPage), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('冲突已关闭'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '保留本机版本'));
    await tester.pumpAndSettle();

    expect(handled, ['transaction-conflict', 'second-conflict']);
    expect(find.text('冲突已关闭'), findsOneWidget);
    AppNotice.dismiss();
    await tester.pump();
  });

  testWidgets('repeated conflict stays open with the latest remote version', (
    tester,
  ) async {
    final refreshed = _transactionRecord(
      remoteSnapshot: const {
        'type': 0,
        'amount': 35,
        'currencyCode': 'CNY',
        'category': '餐饮',
        'happenedAt': '2026-08-30T08:00:00.000',
        'payerPersonUuid': 'person-1',
        'personUuids': ['person-1'],
        'note': '早餐',
      },
    );
    await tester.pumpWidget(
      _scope(
        MaterialApp(
          home: ConflictDetailPage(
            record: _transactionRecord(),
            keepLocal: (id) async => ConflictResolutionOutcome.requiresReview,
            loadLatest: (id) async => refreshed,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '保留本机版本'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ConflictDetailPage), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('云端版本又有变化，请重新确认。'), findsOneWidget);
    AppNotice.dismiss();
    await tester.pump();
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  ConflictDetailPage detail,
) async {
  var closed = false;
  await tester.pumpWidget(
    _scope(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  await Navigator.of(
                    context,
                  ).push<void>(MaterialPageRoute(builder: (_) => detail));
                  setState(() => closed = true);
                },
                child: Text(closed ? '冲突已关闭' : '打开冲突'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _scope(Widget child) => ProviderScope(child: child);

ConflictRecord _transactionRecord({
  String id = 'transaction-conflict',
  num localAmount = 20,
  ConflictOperation operation = ConflictOperation.update,
  bool remoteDeleted = false,
  Map<String, Object?>? remoteSnapshot,
}) {
  return ConflictRecord(
    id: id,
    accountUuid: 'account-a',
    entityType: ConflictEntityType.transaction,
    ledgerUuid: 'ledger-1',
    localUuid: 'transaction-local',
    remoteUuid: 'transaction-remote',
    operation: operation,
    baseVersion: 2,
    remoteVersion: 3,
    localSnapshot: {
      'type': 0,
      'amount': localAmount,
      'currencyCode': 'CNY',
      'category': '餐饮',
      'happenedAt': '2026-08-30T08:00:00.000',
      'payerPersonUuid': 'person-1',
      'personUuids': ['person-1'],
      'note': '早餐',
    },
    remoteSnapshot:
        remoteSnapshot ??
        const {
          'type': 0,
          'amount': 25,
          'currencyCode': 'CNY',
          'category': '餐饮',
          'happenedAt': '2026-08-30T08:00:00.000',
          'payerPersonUuid': 'person-1',
          'personUuids': ['person-1'],
          'note': '早餐',
        },
    remoteDeleted: remoteDeleted,
    detectedAt: DateTime.utc(2026, 8, 30, 9),
  );
}
