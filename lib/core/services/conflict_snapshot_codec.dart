import '../config/avatar_config.dart';
import '../database/database_service.dart';
import '../models/conflict_record.dart';
import '../models/ledger.dart';
import '../models/local_profile.dart';
import '../models/person.dart';
import '../models/transaction_record.dart';
import '../preferences/local_profile_store.dart';
import 'sync_identity_resolver.dart';

class ConflictSnapshotCodec {
  ConflictSnapshotCodec({
    required DatabaseService database,
    required LocalProfileStore profileStore,
    SyncIdentityResolver? identityResolver,
  }) : _database = database,
       _profileStore = profileStore,
       _identityResolver = identityResolver ?? SyncIdentityResolver(database);

  final DatabaseService _database;
  final LocalProfileStore _profileStore;
  final SyncIdentityResolver _identityResolver;

  Map<String, Object?> profileSnapshot(
    LocalProfile value, {
    required String accountUuid,
  }) {
    return {
      'uuid': accountUuid,
      'nickname': value.normalizedNickname,
      'avatar': value.personAvatar,
      'version': value.remoteVersion,
    };
  }

  Map<String, Object?> ledgerSnapshot(Ledger value) {
    return {
      'uuid': value.remoteSyncUuid,
      'name': value.name,
      'baseCurrencyCode': value.baseCurrencyCode,
      'exchangeRateToCny': value.exchangeRateToCNY,
      'version': value.version,
      'role': value.role,
      'memberCount': value.memberCount,
      'members': value.members.map(memberSnapshot).toList(),
    };
  }

  Map<String, Object?> memberSnapshot(LedgerMemberSummary value) {
    return {
      'uuid': value.uuid,
      'userUuid': value.userUuid,
      'nickname': value.nickname,
      'avatar': value.avatar,
      'role': value.role,
      'version': value.version,
    };
  }

  Map<String, Object?> personSnapshot(Person value) {
    return {
      'uuid': value.remoteSyncUuid,
      'name': value.name,
      'avatar': value.avatar,
      'linkedUserUuid': value.linkedUserUuid,
      'version': value.version,
    };
  }

  Map<String, Object?> transactionSnapshot(TransactionRecord value) {
    return {
      'uuid': value.uuid,
      'ledgerUuid': value.ledgerUuid,
      'type': value.type,
      'payerPersonUuid': value.payerPersonUuid,
      'amount': value.amount,
      'currencyCode': value.currencyCode,
      'category': value.category,
      'note': value.note,
      'happenedAt': value.createdAt.toIso8601String(),
      'personUuids': List<String>.from(value.personUuids),
      'clientOperationId': value.clientOperationId,
      'createdByUserUuid': value.createdByUserUuid,
      'createdByNickname': value.createdByNickname,
      'createdByAvatar': value.createdByAvatar,
      'version': value.version,
    };
  }

  Map<String, Object?> requestData(ConflictRecord record, int version) {
    if (record.operation != ConflictOperation.update) {
      return {'version': version};
    }

    final snapshot = record.localSnapshot;
    return switch (record.entityType) {
      ConflictEntityType.profile => {
        'nickname': snapshot['nickname'],
        'avatar': snapshot['avatar'],
        'version': version,
      },
      ConflictEntityType.ledger => {
        'name': snapshot['name'],
        'baseCurrencyCode': snapshot['baseCurrencyCode'],
        'exchangeRateToCny': snapshot['exchangeRateToCny'],
        'version': version,
      },
      ConflictEntityType.member => {
        'role': snapshot['role'],
        'version': version,
      },
      ConflictEntityType.person => {
        'name': snapshot['name'],
        'avatar': snapshot['avatar'],
        'linkedUserUuid': snapshot['linkedUserUuid'],
        'version': version,
      },
      ConflictEntityType.transaction => {
        'type': snapshot['type'],
        'payerPersonUuid': snapshot['payerPersonUuid'],
        'amount': snapshot['amount'],
        'currencyCode': snapshot['currencyCode'],
        'category': snapshot['category'],
        'note': snapshot['note'],
        'happenedAt': snapshot['happenedAt'],
        'personUuids': snapshot['personUuids'],
        'version': version,
      },
    };
  }

  Future<void> applyRemote(ConflictRecord record) async {
    switch (record.entityType) {
      case ConflictEntityType.profile:
        await _applyRemoteProfile(record);
      case ConflictEntityType.ledger:
        await _applyRemoteLedger(record);
      case ConflictEntityType.member:
        await _applyRemoteMember(record);
      case ConflictEntityType.person:
        await _applyRemotePerson(record);
      case ConflictEntityType.transaction:
        await _applyRemoteTransaction(record);
    }
  }

  Future<void> applyMutationVersion(ConflictRecord record, int version) async {
    switch (record.entityType) {
      case ConflictEntityType.profile:
        final current = await _profileStore.read();
        await _profileStore.save(
          current.copyWith(
            remoteVersion: version,
            pendingSync: false,
            pendingOperationId: null,
            syncError: null,
            updatedAt: null,
          ),
        );
      case ConflictEntityType.ledger:
        final ledger = await _findLedger(record.localUuid, record.remoteUuid);
        if (ledger == null) return;
        ledger
          ..version = version
          ..isDeleted = _deletedAfterMutation(record, ledger.isDeleted)
          ..pendingSync = false
          ..syncError = null;
        await _database.saveLedger(ledger);
      case ConflictEntityType.member:
        await _applyMemberMutationVersion(record, version);
      case ConflictEntityType.person:
        final person = await _findPerson(record.localUuid, record.remoteUuid);
        if (person == null) return;
        person
          ..version = version
          ..isDeleted = _deletedAfterMutation(record, person.isDeleted)
          ..pendingSync = false
          ..syncError = null;
        await _database.savePerson(person);
      case ConflictEntityType.transaction:
        final match = await _findTransaction(record);
        if (match == null) return;
        match
          ..version = version
          ..isDeleted = _deletedAfterMutation(record, match.isDeleted)
          ..pendingSync = false
          ..syncError = null;
        await _database.saveTransaction(match);
    }
  }

  Future<void> _applyRemoteProfile(ConflictRecord record) async {
    final current = await _profileStore.read();
    final snapshot = record.remoteSnapshot;
    final avatar = _text(snapshot['avatar'], current.personAvatar);
    await _profileStore.save(
      current.copyWith(
        nickname: _text(snapshot['nickname'], current.nickname),
        avatarIcon: AvatarConfig.normalizeKey(avatar),
        remoteVersion: _version(record, snapshot, current.remoteVersion),
        pendingSync: false,
        pendingOperationId: null,
        syncError: null,
        updatedAt: null,
      ),
    );
  }

  Future<void> _applyRemoteLedger(ConflictRecord record) async {
    final snapshot = record.remoteSnapshot;
    final existing = await _findLedger(record.localUuid, record.remoteUuid);
    final ledger =
        existing ??
        (Ledger()
          ..uuid = record.localUuid
          ..name = ''
          ..baseCurrencyCode = 'CNY');
    final members = _memberList(snapshot['members']);
    ledger
      ..name = _text(snapshot['name'], ledger.name)
      ..baseCurrencyCode = _text(
        snapshot['baseCurrencyCode'],
        ledger.baseCurrencyCode,
      )
      ..exchangeRateToCNY = _double(
        snapshot['exchangeRateToCny'],
        ledger.exchangeRateToCNY,
      )
      ..version = _version(record, snapshot, ledger.version)
      ..role = _nullableText(snapshot, 'role', ledger.role)
      ..memberCount = _integer(snapshot['memberCount'], ledger.memberCount)
      ..members = members ?? ledger.members
      ..syncedRemoteUuid = ledger.uuid == record.remoteUuid
          ? ledger.syncedRemoteUuid
          : record.remoteUuid
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged
      ..isDeleted = record.remoteDeleted
      ..pendingSync = false
      ..syncError = null;
    await _database.saveLedger(ledger);
  }

  Future<void> _applyRemoteMember(ConflictRecord record) async {
    final ledger = await _ledgerForRecord(record);
    if (ledger == null) {
      throw StateError('找不到冲突成员所属账本');
    }
    final index = ledger.members.indexWhere((member) {
      return member.uuid == record.localUuid ||
          member.uuid == record.remoteUuid;
    });
    if (record.remoteDeleted) {
      if (index != -1) {
        ledger.members = List<LedgerMemberSummary>.from(ledger.members)
          ..removeAt(index);
        ledger.memberCount = ledger.members.length;
        await _database.saveLedger(ledger);
      }
      return;
    }

    final existing = index == -1 ? null : ledger.members[index];
    final snapshot = record.remoteSnapshot;
    final member = LedgerMemberSummary(
      uuid: _text(snapshot['uuid'], existing?.uuid ?? record.remoteUuid),
      userUuid: _nullableText(snapshot, 'userUuid', existing?.userUuid),
      nickname: _nullableText(snapshot, 'nickname', existing?.nickname),
      avatar: _nullableText(snapshot, 'avatar', existing?.avatar),
      role: _nullableText(snapshot, 'role', existing?.role),
      version: _version(record, snapshot, existing?.version ?? 1),
    );
    final members = List<LedgerMemberSummary>.from(ledger.members);
    if (index == -1) {
      members.add(member);
    } else {
      members[index] = member;
    }
    ledger
      ..members = members
      ..memberCount = _integer(
        snapshot['memberCount'],
        ledger.memberCount < members.length
            ? members.length
            : ledger.memberCount,
      );
    await _database.saveLedger(ledger);
  }

  Future<void> _applyRemotePerson(ConflictRecord record) async {
    final snapshot = record.remoteSnapshot;
    final existing = await _findPerson(record.localUuid, record.remoteUuid);
    final person =
        existing ??
        (Person()
          ..uuid = record.localUuid
          ..name = '参与人');
    person
      ..name = _text(snapshot['name'], person.name)
      ..avatar = AvatarConfig.normalizeAvatar(
        _text(snapshot['avatar'], person.avatar),
      )
      ..linkedUserUuid = _nullableText(
        snapshot,
        'linkedUserUuid',
        person.linkedUserUuid,
      )
      ..version = _version(record, snapshot, person.version)
      ..syncedRemoteUuid = person.uuid == record.remoteUuid
          ? person.syncedRemoteUuid
          : record.remoteUuid
      ..isDeleted = record.remoteDeleted
      ..pendingSync = false
      ..syncError = null;
    await _database.savePerson(person);
  }

  Future<void> _applyRemoteTransaction(ConflictRecord record) async {
    final snapshot = record.remoteSnapshot;
    final existing = await _findTransaction(record);
    final ledgerUuid = existing?.ledgerUuid ?? await _localLedgerUuid(record);
    if (ledgerUuid == null) {
      throw StateError('找不到冲突流水所属账本');
    }
    final remotePayerUuid = _optionalText(snapshot['payerPersonUuid']);
    final remotePersonUuids = _stringList(snapshot['personUuids']);
    final localPayerUuid = remotePayerUuid == null
        ? null
        : await _identityResolver.resolveLocalPersonUuid(remotePayerUuid);
    final localPersonUuids = await _identityResolver.resolveLocalPersonUuids(
      remotePersonUuids,
    );
    final remoteUuid = _text(snapshot['uuid'], record.remoteUuid);
    final replacesTemporaryIdentity =
        existing != null && existing.uuid != remoteUuid;
    if (replacesTemporaryIdentity) {
      existing
        ..isDeleted = true
        ..pendingSync = false
        ..syncError = null;
      await _database.saveTransaction(existing);
    }
    final transaction =
        (replacesTemporaryIdentity ? _copyTransaction(existing) : existing) ??
        (TransactionRecord()
          ..uuid = remoteUuid
          ..ledgerUuid = ledgerUuid
          ..amount = 0
          ..currencyCode = 'CNY'
          ..category = ''
          ..note = ''
          ..createdAt = DateTime.now());
    transaction
      ..uuid = remoteUuid
      ..ledgerUuid = ledgerUuid
      ..type = _integer(snapshot['type'], transaction.type)
      ..payerPersonUuid = localPayerUuid
      ..amount = _double(snapshot['amount'], transaction.amount)
      ..currencyCode = _text(snapshot['currencyCode'], transaction.currencyCode)
      ..category = _text(snapshot['category'], transaction.category)
      ..note = _text(snapshot['note'], transaction.note)
      ..personUuids = remotePersonUuids.isEmpty
          ? transaction.personUuids
          : localPersonUuids
      ..createdByUserUuid = _nullableText(
        snapshot,
        'createdByUserUuid',
        transaction.createdByUserUuid,
      )
      ..createdByNickname = _nullableText(
        snapshot,
        'createdByNickname',
        transaction.createdByNickname,
      )
      ..createdByAvatar = _nullableText(
        snapshot,
        'createdByAvatar',
        transaction.createdByAvatar,
      )
      ..createdAt = _dateTime(
        snapshot['happenedAt'] ?? snapshot['createdAt'],
        transaction.createdAt,
      )
      ..version = _version(record, snapshot, transaction.version)
      ..isDeleted = record.remoteDeleted
      ..pendingSync = false
      ..syncError = null;
    await _database.saveTransaction(transaction);
  }

  static TransactionRecord _copyTransaction(TransactionRecord source) {
    return TransactionRecord()
      ..id = 0
      ..uuid = source.uuid
      ..ledgerUuid = source.ledgerUuid
      ..type = source.type
      ..payerPersonUuid = source.payerPersonUuid
      ..clientOperationId = source.clientOperationId
      ..version = source.version
      ..amount = source.amount
      ..currencyCode = source.currencyCode
      ..category = source.category
      ..personUuids = List<String>.from(source.personUuids)
      ..note = source.note
      ..createdByUserUuid = source.createdByUserUuid
      ..createdByNickname = source.createdByNickname
      ..createdByAvatar = source.createdByAvatar
      ..createdAt = source.createdAt
      ..pendingSync = source.pendingSync
      ..syncError = source.syncError
      ..isDeleted = source.isDeleted;
  }

  Future<void> _applyMemberMutationVersion(
    ConflictRecord record,
    int version,
  ) async {
    final ledger = await _ledgerForRecord(record);
    if (ledger == null) return;
    final index = ledger.members.indexWhere((member) {
      return member.uuid == record.localUuid ||
          member.uuid == record.remoteUuid;
    });
    if (index == -1) return;
    if (record.operation == ConflictOperation.delete) {
      ledger.members = List<LedgerMemberSummary>.from(ledger.members)
        ..removeAt(index);
      ledger.memberCount = ledger.members.length;
    } else {
      final current = ledger.members[index];
      final members = List<LedgerMemberSummary>.from(ledger.members);
      members[index] = LedgerMemberSummary(
        uuid: current.uuid,
        userUuid: current.userUuid,
        nickname: current.nickname,
        avatar: current.avatar,
        role: current.role,
        version: version,
      );
      ledger.members = members;
    }
    await _database.saveLedger(ledger);
  }

  bool _deletedAfterMutation(ConflictRecord record, bool current) {
    return switch (record.operation) {
      ConflictOperation.update => current,
      ConflictOperation.delete => true,
      ConflictOperation.restore => false,
    };
  }

  Future<Ledger?> _findLedger(String localUuid, String remoteUuid) async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    return ledgers.where((ledger) {
      return ledger.uuid == localUuid ||
          ledger.uuid == remoteUuid ||
          ledger.syncedRemoteUuid == remoteUuid;
    }).firstOrNull;
  }

  Future<Ledger?> _ledgerForRecord(ConflictRecord record) async {
    final ledgerUuid = record.ledgerUuid;
    if (ledgerUuid == null) return null;
    return _findLedger(ledgerUuid, ledgerUuid);
  }

  Future<Person?> _findPerson(String localUuid, String remoteUuid) async {
    final people = await _database.getAllPeople(includeDeleted: true);
    return people.where((person) {
      return person.uuid == localUuid ||
          person.uuid == remoteUuid ||
          person.syncedRemoteUuid == remoteUuid;
    }).firstOrNull;
  }

  Future<TransactionRecord?> _findTransaction(ConflictRecord record) async {
    final ledgerUuid = await _localLedgerUuid(record);
    if (ledgerUuid == null) return null;
    final transactions = await _database.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: true,
    );
    return transactions.where((transaction) {
      return transaction.uuid == record.localUuid ||
          transaction.uuid == record.remoteUuid;
    }).firstOrNull;
  }

  Future<String?> _localLedgerUuid(ConflictRecord record) async {
    final ledgerUuid = record.ledgerUuid;
    if (ledgerUuid == null) return null;
    final ledger = await _findLedger(ledgerUuid, ledgerUuid);
    return ledger?.uuid ?? ledgerUuid;
  }

  static List<LedgerMemberSummary>? _memberList(Object? value) {
    if (value is! List<dynamic>) return null;
    return value.whereType<Map<dynamic, dynamic>>().map((raw) {
      final map = raw.cast<String, Object?>();
      return LedgerMemberSummary(
        uuid: _text(map['uuid'], ''),
        userUuid: _optionalText(map['userUuid']),
        nickname: _optionalText(map['nickname']),
        avatar: _optionalText(map['avatar']),
        role: _optionalText(map['role']),
        version: _integer(map['version'], 1),
      );
    }).toList();
  }

  static int _version(
    ConflictRecord record,
    Map<String, Object?> snapshot,
    int fallback,
  ) {
    return _integer(snapshot['version'], record.remoteVersion ?? fallback);
  }

  static String _text(Object? value, String fallback) {
    return _optionalText(value) ?? fallback;
  }

  static String? _nullableText(
    Map<String, Object?> snapshot,
    String key,
    String? fallback,
  ) {
    return snapshot.containsKey(key) ? _optionalText(snapshot[key]) : fallback;
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _integer(Object? value, int fallback) {
    return value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  }

  static double _double(Object? value, double fallback) {
    return value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? fallback;
  }

  static DateTime _dateTime(Object? value, DateTime fallback) {
    return DateTime.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<dynamic>) return const [];
    return value.map((item) => item.toString()).toList();
  }
}
