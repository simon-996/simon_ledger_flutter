import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/features/conflicts/presentation/screens/conflict_center_page.dart';

void main() {
  testWidgets('conflict center groups account and ledgers oldest first', (
    tester,
  ) async {
    final records = [
      _record(
        id: 'profile',
        type: ConflictEntityType.profile,
        detectedAt: DateTime.utc(2026, 8, 20, 8),
        localSnapshot: const {'nickname': '本地昵称'},
      ),
      _record(
        id: 'breakfast',
        type: ConflictEntityType.transaction,
        ledgerUuid: 'ledger-1',
        detectedAt: DateTime.utc(2026, 8, 20, 9),
        localSnapshot: const {'category': '早餐'},
      ),
      _record(
        id: 'person',
        type: ConflictEntityType.person,
        ledgerUuid: 'ledger-1',
        detectedAt: DateTime.utc(2026, 8, 20, 10),
        localSnapshot: const {'name': '小明'},
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conflictRecordsProvider.overrideWith((ref) async => records),
          conflictLedgerNamesProvider.overrideWith(
            (ref) async => const {'ledger-1': '家庭账本'},
          ),
        ],
        child: const MaterialApp(home: ConflictCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('数据冲突'), findsOneWidget);
    expect(find.text('账户资料'), findsWidgets);
    expect(find.text('家庭账本'), findsOneWidget);
    expect(find.text('流水 · 早餐'), findsOneWidget);
    expect(find.text('参与人 · 小明'), findsOneWidget);

    final breakfastTop = tester.getTopLeft(find.text('流水 · 早餐')).dy;
    final personTop = tester.getTopLeft(find.text('参与人 · 小明')).dy;
    expect(breakfastTop, lessThan(personTop));
  });

  testWidgets('conflict center has a calm empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conflictRecordsProvider.overrideWith((ref) async => const []),
          conflictLedgerNamesProvider.overrideWith((ref) async => const {}),
        ],
        child: const MaterialApp(home: ConflictCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有待确认的数据'), findsOneWidget);
    expect(find.text('检测到版本差异时，会在这里逐项确认。'), findsOneWidget);
  });
}

ConflictRecord _record({
  required String id,
  required ConflictEntityType type,
  required DateTime detectedAt,
  String? ledgerUuid,
  Map<String, Object?> localSnapshot = const {},
}) {
  return ConflictRecord(
    id: id,
    entityType: type,
    ledgerUuid: ledgerUuid,
    localUuid: '$id-local',
    remoteUuid: '$id-remote',
    operation: ConflictOperation.update,
    baseVersion: 1,
    remoteVersion: 2,
    localSnapshot: localSnapshot,
    remoteSnapshot: const {},
    remoteDeleted: false,
    detectedAt: detectedAt,
  );
}
