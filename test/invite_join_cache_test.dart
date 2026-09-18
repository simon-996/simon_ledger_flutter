import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/invite_join_result.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/services/invite_join_cache.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'parses complete join envelope while retaining legacy invite fields',
    () {
      final result = InviteJoinResult.fromJson(_completeJoinJson);

      expect(result.isComplete, isTrue);
      expect(result.invite.code, 'ABCD1234');
      expect(result.ledger!.uuid, 'remote-ledger');
      expect(result.member!.userUuid, 'remote-user');
      expect(result.person!.uuid, 'remote-person');
      expect(result.person!.version, 3);
    },
  );

  test(
    'parses legacy flat join response without requiring nested snapshots',
    () {
      final result = InviteJoinResult.fromJson(_legacyJoinJson);

      expect(result.isComplete, isFalse);
      expect(result.invite.code, 'ABCD1234');
      expect(result.ledger, isNull);
      expect(result.person, isNull);
    },
  );

  test(
    'caches a joined ledger and linked person using remote identities',
    () async {
      final database = DatabaseService();
      await InviteJoinCache(database).apply(
        InviteJoinResult.fromJson(_completeJoinJson),
        accountUuid: 'remote-user',
      );

      final ledgers = await database.getAllLedgers(includeDeleted: true);
      final people = await database.getAllPeople(includeDeleted: true);
      expect(ledgers, hasLength(1));
      expect(ledgers.single.uuid, 'remote-ledger');
      expect(ledgers.single.syncedRemoteUuid, 'remote-ledger');
      expect(ledgers.single.cloudPolicy, LedgerCloudPolicy.cloudManaged);
      expect(ledgers.single.role, 'editor');
      expect(ledgers.single.personUuids, ['remote-person']);
      expect(people, hasLength(1));
      expect(people.single.uuid, 'remote-person');
      expect(people.single.linkedUserUuid, 'remote-user');
      expect(people.single.syncedRemoteUuid, 'remote-person');
      expect(people.single.name, 'Simon');
    },
  );

  test('reuses local identities and preserves pending local changes', () async {
    final database = DatabaseService();
    await database.saveLedger(
      Ledger()
        ..uuid = 'local-ledger'
        ..name = '本地未同步名称'
        ..baseCurrencyCode = 'CNY'
        ..syncedRemoteUuid = 'remote-ledger'
        ..pendingSync = true
        ..personUuids = ['local-person'],
    );
    await database.savePerson(
      Person()
        ..uuid = 'local-person'
        ..name = '本地参与人修改'
        ..linkedUserUuid = 'remote-user'
        ..syncedRemoteUuid = 'remote-person'
        ..pendingSync = true,
    );

    await InviteJoinCache(database).apply(
      InviteJoinResult.fromJson(_completeJoinJson),
      accountUuid: 'remote-user',
    );

    final ledger = (await database.getAllLedgers(includeDeleted: true)).single;
    final person = (await database.getAllPeople(includeDeleted: true)).single;
    expect(ledger.uuid, 'local-ledger');
    expect(ledger.name, '本地未同步名称');
    expect(ledger.personUuids, ['local-person']);
    expect(ledger.isDeleted, isFalse);
    expect(person.uuid, 'local-person');
    expect(person.name, '本地参与人修改');
    expect(person.isDeleted, isFalse);
  });
}

final _completeJoinJson = <String, dynamic>{
  'code': 'ABCD1234',
  'ledgerUuid': 'remote-ledger',
  'ledgerName': '旅行账本',
  'ledgerBaseCurrencyCode': 'CNY',
  'ledgerMemberCount': 2,
  'ledgerMembers': const [],
  'role': 'editor',
  'maxUses': 20,
  'usedCount': 3,
  'expiresAt': '2026-09-20T20:00:00',
  'expired': false,
  'disabled': false,
  'invite': {
    'code': 'ABCD1234',
    'ledgerUuid': 'remote-ledger',
    'ledgerName': '旅行账本',
    'ledgerBaseCurrencyCode': 'CNY',
    'ledgerMemberCount': 2,
    'ledgerMembers': [],
    'role': 'editor',
    'maxUses': 20,
    'usedCount': 3,
    'expiresAt': '2026-09-20T20:00:00',
    'expired': false,
    'disabled': false,
  },
  'ledger': {
    'uuid': 'remote-ledger',
    'name': '旅行账本',
    'baseCurrencyCode': 'CNY',
    'exchangeRateToCny': 1,
    'version': 4,
    'role': 'editor',
    'memberCount': 2,
    'members': [],
  },
  'member': {
    'uuid': 'remote-member',
    'userUuid': 'remote-user',
    'nickname': 'Simon',
    'avatar': '😎',
    'role': 'editor',
    'status': 1,
    'version': 2,
  },
  'person': {
    'uuid': 'remote-person',
    'ledgerUuid': 'remote-ledger',
    'linkedUserUuid': 'remote-user',
    'name': 'Simon',
    'avatar': '😎',
    'version': 3,
  },
};

final _legacyJoinJson = <String, dynamic>{
  'code': 'ABCD1234',
  'ledgerUuid': 'remote-ledger',
  'ledgerName': '旅行账本',
  'ledgerBaseCurrencyCode': 'CNY',
  'ledgerMemberCount': 1,
  'ledgerMembers': [],
  'role': 'editor',
  'usedCount': 1,
  'expiresAt': '2026-09-20T20:00:00',
  'expired': false,
  'disabled': false,
};
