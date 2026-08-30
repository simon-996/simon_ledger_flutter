import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';

void main() {
  testWidgets('conflict providers refresh when the store changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = ConflictStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [conflictStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              return Text('冲突 ${ref.watch(conflictCountProvider)}');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('冲突 0'), findsOneWidget);

    await store.upsert(
      ConflictRecord(
        id: 'conflict-1',
        entityType: ConflictEntityType.profile,
        ledgerUuid: null,
        localUuid: 'profile-local',
        remoteUuid: 'profile-remote',
        operation: ConflictOperation.update,
        baseVersion: 1,
        remoteVersion: 2,
        localSnapshot: const {'nickname': '本机'},
        remoteSnapshot: const {'nickname': '云端'},
        remoteDeleted: false,
        detectedAt: DateTime.utc(2026, 8, 30),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('冲突 1'), findsOneWidget);
  });
}
