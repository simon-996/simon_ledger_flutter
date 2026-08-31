import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/services/conflict_snapshot_codec.dart';

void main() {
  late DatabaseService database;
  late LocalProfileStore profileStore;
  late ConflictSnapshotCodec codec;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = DatabaseService();
    profileStore = const LocalProfileStore();
    codec = ConflictSnapshotCodec(
      database: database,
      profileStore: profileStore,
    );
  });

  test('profile snapshot contains no account credentials', () {
    final snapshot = codec.profileSnapshot(
      const LocalProfile(
        nickname: '本机昵称',
        avatarIcon: 'star',
        remoteVersion: 3,
      ),
      accountUuid: 'user-1',
    );

    expect(snapshot, containsPair('avatar', '⭐'));
    expect(
      snapshot.keys,
      containsAll(['uuid', 'nickname', 'avatar', 'version']),
    );
    expect(snapshot.keys, isNot(contains('email')));
    expect(snapshot.keys, isNot(contains('phone')));
    expect(snapshot.keys, isNot(contains('token')));
  });

  test('entity snapshots use API field names and remote identity mappings', () {
    final ledger = Ledger()
      ..uuid = 'ledger-local'
      ..syncedRemoteUuid = 'ledger-remote'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'USD'
      ..exchangeRateToCNY = 7.2
      ..version = 3
      ..members = const [
        LedgerMemberSummary(
          uuid: 'member-1',
          nickname: '小明',
          role: 'editor',
          version: 4,
        ),
      ];
    final person = Person()
      ..uuid = 'person-local'
      ..syncedRemoteUuid = 'person-remote'
      ..name = '小明'
      ..avatar = '🐶'
      ..version = 5;
    final transaction = TransactionRecord()
      ..uuid = 'transaction-1'
      ..ledgerUuid = 'ledger-local'
      ..type = 0
      ..payerPersonUuid = 'person-local'
      ..clientOperationId = 'operation-1'
      ..amount = 30
      ..currencyCode = 'USD'
      ..category = '餐饮'
      ..note = '早餐'
      ..personUuids = ['person-local']
      ..createdAt = DateTime(2026, 8, 26, 8)
      ..version = 6;

    expect(
      codec.ledgerSnapshot(ledger),
      containsPair('exchangeRateToCny', 7.2),
    );
    expect(codec.ledgerSnapshot(ledger)['uuid'], 'ledger-remote');
    expect(
      (codec.ledgerSnapshot(ledger)['members']! as List).single,
      containsPair('version', 4),
    );
    expect(codec.personSnapshot(person)['uuid'], 'person-remote');
    expect(codec.personSnapshot(person)['version'], 5);
    expect(
      codec.transactionSnapshot(transaction),
      containsPair('happenedAt', '2026-08-26T08:00:00.000'),
    );
    expect(
      codec.transactionSnapshot(transaction)['clientOperationId'],
      'operation-1',
    );
  });

  test('request maps expose only the fields accepted by each update API', () {
    expect(
      codec.requestData(
        _record(
          entityType: ConflictEntityType.ledger,
          localSnapshot: const {
            'uuid': 'ledger-remote',
            'name': '旅行账本',
            'baseCurrencyCode': 'USD',
            'exchangeRateToCny': 7.2,
            'version': 4,
            'role': 'owner',
          },
        ),
        5,
      ),
      {
        'name': '旅行账本',
        'baseCurrencyCode': 'USD',
        'exchangeRateToCny': 7.2,
        'version': 5,
      },
    );
    expect(
      codec.requestData(
        _record(
          entityType: ConflictEntityType.member,
          localSnapshot: const {'role': 'editor', 'nickname': '小明'},
        ),
        2,
      ),
      {'role': 'editor', 'version': 2},
    );
    expect(
      codec.requestData(
        _record(
          entityType: ConflictEntityType.person,
          localSnapshot: const {
            'name': '小红',
            'avatar': '🐱',
            'linkedUserUuid': 'user-2',
            'pendingLedgerUuid': 'local-only',
          },
        ),
        6,
      ),
      {'name': '小红', 'avatar': '🐱', 'linkedUserUuid': 'user-2', 'version': 6},
    );
    expect(
      codec.requestData(
        _record(
          entityType: ConflictEntityType.transaction,
          localSnapshot: const {
            'uuid': 'transaction-1',
            'ledgerUuid': 'ledger-local',
            'type': 0,
            'payerPersonUuid': 'person-remote-1',
            'amount': 88.5,
            'currencyCode': 'CNY',
            'category': '餐饮',
            'note': '晚餐',
            'happenedAt': '2026-08-26T19:30:00.000',
            'personUuids': ['person-remote-1', 'person-remote-2'],
            'clientOperationId': 'operation-1',
          },
        ),
        7,
      ),
      {
        'type': 0,
        'payerPersonUuid': 'person-remote-1',
        'amount': 88.5,
        'currencyCode': 'CNY',
        'category': '餐饮',
        'note': '晚餐',
        'happenedAt': '2026-08-26T19:30:00.000',
        'personUuids': ['person-remote-1', 'person-remote-2'],
        'version': 7,
      },
    );
  });

  test('delete carries only version while restore resubmits local fields', () {
    final deleteRecord = _record(
      operation: ConflictOperation.delete,
      localSnapshot: const {'name': '不应提交'},
    );
    final restoreRecord = _record(
      operation: ConflictOperation.restore,
      localSnapshot: const {
        'name': '恢复后的名称',
        'baseCurrencyCode': 'CNY',
        'exchangeRateToCny': 1.0,
      },
    );

    expect(codec.requestData(deleteRecord, 8), {'version': 8});
    expect(codec.requestData(restoreRecord, 9), {
      'name': '恢复后的名称',
      'baseCurrencyCode': 'CNY',
      'exchangeRateToCny': 1.0,
      'version': 9,
    });
  });

  test(
    'accepting remote profile normalizes avatar and clears pending state',
    () async {
      await profileStore.save(
        LocalProfile(
          nickname: '本机昵称',
          avatarIcon: 'star',
          pendingSync: true,
          pendingOperationId: 'profile-op',
          syncError: '冲突',
          updatedAt: DateTime(2026, 8, 26),
          remoteVersion: 2,
        ),
      );

      await codec.applyRemote(
        _record(
          entityType: ConflictEntityType.profile,
          localUuid: 'user-1',
          remoteUuid: 'user-1',
          remoteVersion: 5,
          remoteSnapshot: const {
            'uuid': 'user-1',
            'nickname': '云端昵称',
            'avatar': '🐱',
            'version': 5,
          },
        ),
      );

      final saved = await profileStore.read();
      expect(saved.nickname, '云端昵称');
      expect(saved.avatarIcon, 'avatar_01');
      expect(saved.remoteVersion, 5);
      expect(saved.pendingSync, isFalse);
      expect(saved.pendingOperationId, isNull);
      expect(saved.syncError, isNull);
    },
  );

  test(
    'accepting remote ledger preserves its local identity mapping',
    () async {
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-local'
          ..syncedRemoteUuid = 'ledger-remote'
          ..name = '本机名称'
          ..baseCurrencyCode = 'CNY'
          ..exchangeRateToCNY = 1
          ..personUuids = ['person-local']
          ..sortOrder = 42
          ..role = 'owner'
          ..cloudPolicy = LedgerCloudPolicy.cloudManaged
          ..pendingSync = true
          ..syncError = '冲突',
      );

      await codec.applyRemote(
        _record(
          entityType: ConflictEntityType.ledger,
          localUuid: 'ledger-local',
          remoteUuid: 'ledger-remote',
          remoteVersion: 4,
          remoteSnapshot: const {
            'uuid': 'ledger-remote',
            'name': '云端名称',
            'baseCurrencyCode': 'USD',
            'exchangeRateToCny': 7.18,
            'version': 4,
            'role': 'admin',
            'memberCount': 3,
          },
        ),
      );

      final saved = (await database.getAllLedgers()).single;
      expect(saved.uuid, 'ledger-local');
      expect(saved.syncedRemoteUuid, 'ledger-remote');
      expect(saved.name, '云端名称');
      expect(saved.baseCurrencyCode, 'USD');
      expect(saved.exchangeRateToCNY, 7.18);
      expect(saved.version, 4);
      expect(saved.role, 'admin');
      expect(saved.memberCount, 3);
      expect(saved.personUuids, ['person-local']);
      expect(saved.sortOrder, 42);
      expect(saved.pendingSync, isFalse);
      expect(saved.syncError, isNull);
    },
  );

  test('accepting remote member replaces only that cached member', () async {
    await database.saveLedger(
      Ledger()
        ..uuid = 'ledger-local'
        ..syncedRemoteUuid = 'ledger-remote'
        ..name = '共享账本'
        ..baseCurrencyCode = 'CNY'
        ..members = const [
          LedgerMemberSummary(uuid: 'member-1', nickname: '甲', role: 'editor'),
          LedgerMemberSummary(uuid: 'member-2', nickname: '乙', role: 'viewer'),
        ],
    );

    await codec.applyRemote(
      _record(
        entityType: ConflictEntityType.member,
        ledgerUuid: 'ledger-local',
        localUuid: 'member-2',
        remoteUuid: 'member-2',
        remoteVersion: 3,
        remoteSnapshot: const {
          'uuid': 'member-2',
          'userUuid': 'user-2',
          'nickname': '乙（云端）',
          'avatar': '🐶',
          'role': 'editor',
          'version': 3,
        },
      ),
    );

    final members = (await database.getAllLedgers()).single.members;
    expect(members, hasLength(2));
    expect(members.first.nickname, '甲');
    expect(members.last.nickname, '乙（云端）');
    expect(members.last.role, 'editor');
    expect(members.last.version, 3);
  });

  test(
    'accepting an active remote membership restores a locally hidden ledger',
    () async {
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-local'
          ..syncedRemoteUuid = 'ledger-remote'
          ..name = '共享账本'
          ..baseCurrencyCode = 'CNY'
          ..role = 'editor'
          ..isDeleted = true
          ..members = const [
            LedgerMemberSummary(
              uuid: 'member-self',
              nickname: '本人',
              role: 'editor',
              version: 2,
            ),
          ],
      );

      await codec.applyRemote(
        _record(
          entityType: ConflictEntityType.member,
          ledgerUuid: 'ledger-local',
          localUuid: 'member-self',
          remoteUuid: 'member-self',
          operation: ConflictOperation.delete,
          localSnapshot: const {
            'uuid': 'member-self',
            'role': 'editor',
            'version': 2,
            'leaveLedger': true,
          },
          remoteVersion: 3,
          remoteSnapshot: const {
            'uuid': 'member-self',
            'nickname': '本人',
            'role': 'editor',
            'version': 3,
          },
        ),
      );

      final visible = await database.getAllLedgers();
      expect(visible, hasLength(1));
      expect(visible.single.isDeleted, isFalse);
      expect(visible.single.members.single.version, 3);
    },
  );

  test('accepting remote person preserves the local person uuid', () async {
    await database.savePerson(
      Person()
        ..uuid = 'person-local'
        ..syncedRemoteUuid = 'person-remote'
        ..name = '本机参与人'
        ..pendingLedgerUuid = 'ledger-local'
        ..pendingSync = true
        ..syncError = '冲突',
    );

    await codec.applyRemote(
      _record(
        entityType: ConflictEntityType.person,
        ledgerUuid: 'ledger-local',
        localUuid: 'person-local',
        remoteUuid: 'person-remote',
        remoteVersion: 8,
        remoteSnapshot: const {
          'uuid': 'person-remote',
          'name': '云端参与人',
          'avatar': '🦊',
          'linkedUserUuid': 'user-3',
          'version': 8,
        },
      ),
    );

    final saved = (await database.getAllPeople()).single;
    expect(saved.uuid, 'person-local');
    expect(saved.syncedRemoteUuid, 'person-remote');
    expect(saved.name, '云端参与人');
    expect(saved.avatar, '🦊');
    expect(saved.linkedUserUuid, 'user-3');
    expect(saved.pendingLedgerUuid, 'ledger-local');
    expect(saved.version, 8);
    expect(saved.pendingSync, isFalse);
    expect(saved.syncError, isNull);
  });

  test(
    'accepting remote transaction maps people back to local cache identities',
    () async {
      await database.savePerson(
        Person()
          ..uuid = 'person-local-1'
          ..syncedRemoteUuid = 'person-remote-1'
          ..name = '甲',
      );
      await database.savePerson(
        Person()
          ..uuid = 'person-local-2'
          ..syncedRemoteUuid = 'person-remote-2'
          ..name = '乙',
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'transaction-remote'
          ..ledgerUuid = 'ledger-local'
          ..clientOperationId = 'operation-1'
          ..type = 0
          ..payerPersonUuid = 'person-local-1'
          ..amount = 80
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..personUuids = ['person-local-1']
          ..note = '本机备注'
          ..createdAt = DateTime(2026, 8, 25)
          ..pendingSync = true
          ..syncError = '冲突',
      );

      await codec.applyRemote(
        _record(
          entityType: ConflictEntityType.transaction,
          ledgerUuid: 'ledger-local',
          localUuid: 'transaction-remote',
          remoteUuid: 'transaction-remote',
          remoteVersion: 9,
          remoteSnapshot: const {
            'uuid': 'transaction-remote',
            'ledgerUuid': 'ledger-remote',
            'type': 0,
            'payerPersonUuid': 'person-remote-2',
            'amount': 99.5,
            'currencyCode': 'USD',
            'category': '交通',
            'note': '云端备注',
            'happenedAt': '2026-08-26T08:30:00.000',
            'personUuids': ['person-remote-1', 'person-remote-2'],
            'version': 9,
          },
        ),
      );

      final saved = (await database.getTransactionsForLedger(
        'ledger-local',
      )).single;
      expect(saved.uuid, 'transaction-remote');
      expect(saved.ledgerUuid, 'ledger-local');
      expect(saved.clientOperationId, 'operation-1');
      expect(saved.payerPersonUuid, 'person-local-2');
      expect(saved.personUuids, ['person-local-1', 'person-local-2']);
      expect(saved.amount, 99.5);
      expect(saved.currencyCode, 'USD');
      expect(saved.category, '交通');
      expect(saved.note, '云端备注');
      expect(saved.createdAt, DateTime(2026, 8, 26, 8, 30));
      expect(saved.version, 9);
      expect(saved.pendingSync, isFalse);
      expect(saved.syncError, isNull);
    },
  );

  test(
    'accepting a remote transaction replaces a temporary local identity',
    () async {
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'transaction-local'
          ..ledgerUuid = 'ledger-local'
          ..clientOperationId = 'operation-1'
          ..amount = 20
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..note = ''
          ..personUuids = ['person-1']
          ..createdAt = DateTime(2026, 8, 26)
          ..pendingSync = true,
      );

      await codec.applyRemote(
        _record(
          entityType: ConflictEntityType.transaction,
          ledgerUuid: 'ledger-local',
          localUuid: 'transaction-local',
          remoteUuid: 'transaction-remote',
          remoteVersion: 2,
          remoteSnapshot: const {
            'uuid': 'transaction-remote',
            'type': 0,
            'amount': 25,
            'currencyCode': 'CNY',
            'category': '餐饮',
            'note': '',
            'happenedAt': '2026-08-26T00:00:00.000',
            'personUuids': ['person-1'],
            'version': 2,
          },
        ),
      );

      final visible = await database.getTransactionsForLedger('ledger-local');
      final all = await database.getTransactionsForLedger(
        'ledger-local',
        includeDeleted: true,
      );
      expect(visible, hasLength(1));
      expect(visible.single.uuid, 'transaction-remote');
      expect(visible.single.clientOperationId, 'operation-1');
      expect(all, hasLength(2));
      expect(
        all.singleWhere((item) => item.uuid == 'transaction-local').isDeleted,
        isTrue,
      );
    },
  );
}

ConflictRecord _record({
  ConflictEntityType entityType = ConflictEntityType.ledger,
  String? ledgerUuid = 'ledger-local',
  String localUuid = 'local-uuid',
  String remoteUuid = 'remote-uuid',
  ConflictOperation operation = ConflictOperation.update,
  int? remoteVersion = 2,
  Map<String, Object?> localSnapshot = const {},
  Map<String, Object?> remoteSnapshot = const {},
  bool remoteDeleted = false,
}) {
  return ConflictRecord(
    id: 'conflict-1',
    accountUuid: 'account-a',
    entityType: entityType,
    ledgerUuid: ledgerUuid,
    localUuid: localUuid,
    remoteUuid: remoteUuid,
    operation: operation,
    baseVersion: 1,
    remoteVersion: remoteVersion,
    localSnapshot: localSnapshot,
    remoteSnapshot: remoteSnapshot,
    remoteDeleted: remoteDeleted,
    detectedAt: DateTime(2026, 8, 26),
  );
}
