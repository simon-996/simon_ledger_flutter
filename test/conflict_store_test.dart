import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round trips records in oldest first order', () async {
    final store = ConflictStore();
    await store.upsert(
      _conflict(
        id: 'newer',
        remoteUuid: 'transaction-2',
        remoteVersion: 4,
        detectedAt: DateTime(2026, 8, 26, 10),
      ),
    );
    await store.upsert(
      _conflict(
        id: 'older',
        remoteUuid: 'transaction-1',
        remoteVersion: 2,
        detectedAt: DateTime(2026, 8, 26, 9),
      ),
    );

    final records = await ConflictStore().readAll();

    expect(records.map((record) => record.id), ['older', 'newer']);
    expect(records.first.localSnapshot['personUuids'], ['person-1']);
    expect(records.first.remoteSnapshot['amount'], 18.5);
  });

  test(
    'upsert replaces one visible conflict for the same remote entity',
    () async {
      final store = ConflictStore();
      final detectedAt = DateTime(2026, 8, 26, 9);
      await store.upsert(
        _conflict(id: 'original-id', remoteVersion: 2, detectedAt: detectedAt),
      );
      await store.upsert(
        _conflict(
          id: 'replacement-id',
          remoteVersion: 3,
          detectedAt: DateTime(2026, 8, 26, 11),
          state: ConflictState.failed,
        ),
      );

      final records = await store.readAll();

      expect(records, hasLength(1));
      expect(records.single.id, 'original-id');
      expect(records.single.detectedAt, detectedAt);
      expect(records.single.remoteVersion, 3);
      expect(records.single.state, ConflictState.unresolved);
      expect(records.single.error, isNull);
    },
  );

  test('scopes records and de-duplication to the owning account', () async {
    final store = ConflictStore();
    await store.upsert(
      _conflict(id: 'account-a-conflict', accountUuid: 'account-a'),
    );
    await store.upsert(
      _conflict(id: 'account-b-conflict', accountUuid: 'account-b'),
    );

    final accountA = await store.readAll(accountUuid: 'account-a');
    final accountB = await store.readAll(accountUuid: 'account-b');

    expect(accountA.map((record) => record.id), ['account-a-conflict']);
    expect(accountB.map((record) => record.id), ['account-b-conflict']);
    expect(await store.readAll(), hasLength(2));
  });

  test('updates state and removes a resolved record', () async {
    final store = ConflictStore();
    await store.upsert(_conflict());

    await store.updateState(
      'conflict-1',
      'account-a',
      ConflictState.queuedLocal,
      error: '等待联网提交',
    );
    final queued = (await store.readAll()).single;
    expect(queued.state, ConflictState.queuedLocal);
    expect(queued.error, '等待联网提交');

    await store.remove('conflict-1', accountUuid: 'account-a');
    expect(await store.readAll(), isEmpty);
  });

  test('treats a corrupt stored value as an empty queue', () async {
    SharedPreferences.setMockInitialValues({
      'local_store.conflicts.v1': jsonEncode({'unexpected': true}),
    });

    expect(await ConflictStore().readAll(), isEmpty);
  });

  test('retains valid records when one persisted entry is malformed', () async {
    final valid = _conflict(id: 'valid-1');
    SharedPreferences.setMockInitialValues({
      ConflictStore.storageKey: jsonEncode([
        valid.toJson(),
        {'id': 'broken-only'},
      ]),
    });
    final store = ConflictStore();

    expect((await store.readAll()).map((record) => record.id), ['valid-1']);

    await store.upsert(_conflict(id: 'valid-2', remoteUuid: 'transaction-2'));

    expect((await store.readAll()).map((record) => record.id), [
      'valid-1',
      'valid-2',
    ]);
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        jsonDecode(prefs.getString(ConflictStore.storageKey)!) as List<dynamic>;
    expect(persisted, hasLength(3));
    expect(
      persisted.whereType<Map>().any((item) => item['id'] == 'broken-only'),
      isTrue,
    );
  });
}

ConflictRecord _conflict({
  String id = 'conflict-1',
  String accountUuid = 'account-a',
  String remoteUuid = 'transaction-1',
  int remoteVersion = 2,
  DateTime? detectedAt,
  ConflictState state = ConflictState.unresolved,
}) {
  return ConflictRecord(
    id: id,
    accountUuid: accountUuid,
    entityType: ConflictEntityType.transaction,
    ledgerUuid: 'ledger-1',
    localUuid: 'local-transaction-1',
    remoteUuid: remoteUuid,
    operation: ConflictOperation.update,
    baseVersion: 1,
    remoteVersion: remoteVersion,
    localSnapshot: const {
      'amount': 16.0,
      'personUuids': ['person-1'],
    },
    remoteSnapshot: const {'amount': 18.5},
    remoteDeleted: false,
    detectedAt: detectedAt ?? DateTime(2026, 8, 26, 9),
    state: state,
  );
}
