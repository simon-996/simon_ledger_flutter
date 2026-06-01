import 'dart:async';

import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/person.dart';
import '../network/api_client.dart';
import '../network/token_store.dart';
import '../services/sync_identity_resolver.dart';

class CreatedLedgerWithPeople {
  const CreatedLedgerWithPeople({required this.ledger, required this.people});

  final Ledger ledger;
  final List<Person> people;
}

class _LedgerPeopleBatch {
  const _LedgerPeopleBatch({
    required this.peopleByLedgerUuid,
    required this.people,
  });

  final Map<String, List<String>> peopleByLedgerUuid;
  final List<Person> people;
}

abstract class LedgerRepository {
  Future<List<Ledger>> getCachedLedgers({bool includeDeleted = false});

  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false});

  Future<void> saveLedger(Ledger ledger);

  Future<CreatedLedgerWithPeople> createLedgerWithPeople(
    Ledger ledger,
    List<Person> people,
  );

  Future<void> deleteLedger(String uuid);

  Future<void> syncPendingWrites({String? ledgerUuid});
}

class LocalLedgerRepository implements LedgerRepository {
  const LocalLedgerRepository(this._db);

  final DatabaseService _db;

  @override
  Future<List<Ledger>> getCachedLedgers({bool includeDeleted = false}) {
    return getAllLedgers(includeDeleted: includeDeleted);
  }

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: includeDeleted);
    return ledgers.where((ledger) => ledger.isLocalTemporary).toList();
  }

  @override
  Future<void> saveLedger(Ledger ledger) {
    return _db.saveLedger(ledger);
  }

  @override
  Future<CreatedLedgerWithPeople> createLedgerWithPeople(
    Ledger ledger,
    List<Person> people,
  ) async {
    for (final person in people) {
      await _db.savePerson(person);
    }
    ledger.personUuids = people.map((person) => person.uuid).toList();
    await _db.saveLedger(ledger);
    return CreatedLedgerWithPeople(ledger: ledger, people: people);
  }

  @override
  Future<void> deleteLedger(String uuid) {
    return _db.deleteLedger(uuid);
  }

  @override
  Future<void> syncPendingWrites({String? ledgerUuid}) async {}
}

class RemoteLedgerRepository implements LedgerRepository {
  RemoteLedgerRepository({
    required ApiClient apiClient,
    required DatabaseService database,
    TokenStore? tokenStore,
    SyncIdentityResolver? identityResolver,
  }) : _apiClient = apiClient,
       _db = database,
       _tokenStore = tokenStore,
       _identityResolver = identityResolver ?? SyncIdentityResolver(database);

  final ApiClient _apiClient;
  final DatabaseService _db;
  final TokenStore? _tokenStore;
  final SyncIdentityResolver _identityResolver;
  static final Map<String, Future<void>> _pendingLocalLedgerUploads = {};

  @override
  Future<List<Ledger>> getCachedLedgers({bool includeDeleted = false}) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: includeDeleted);
    return _visibleCachedLedgers(ledgers);
  }

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    try {
      await syncPendingWrites();
      final ledgers = await _apiClient.get<List<Ledger>>(
        '/api/ledgers',
        fromJson: (json) =>
            (json! as List<dynamic>).map(_ledgerFromJson).toList(),
      );
      final accountUuid = await _tokenStore?.readAccountUuid();
      for (final ledger in ledgers) {
        ledger.cacheOwnerUserUuid = accountUuid;
      }
      final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
      final cachedPeopleByLedgerUuid = {
        for (final ledger in cachedLedgers) ledger.uuid: ledger.personUuids,
      };
      final cachedSortOrderByRemoteUuid = {
        for (final ledger in cachedLedgers)
          ledger.remoteSyncUuid: ledger.sortOrder,
      };

      if (ledgers.isNotEmpty) {
        try {
          final peopleBatch = await _apiClient.get<_LedgerPeopleBatch>(
            '/api/ledgers/people',
            queryParameters: {
              'ledgerUuids': ledgers.map((ledger) => ledger.uuid).join(','),
            },
            fromJson: _ledgerPeopleBatchFromJson,
          );
          for (final person in peopleBatch.people) {
            await _db.savePerson(person);
          }
          for (final ledger in ledgers) {
            ledger.personUuids =
                peopleBatch.peopleByLedgerUuid[ledger.uuid] ?? const [];
          }
        } catch (_) {
          for (final ledger in ledgers) {
            ledger.personUuids =
                cachedPeopleByLedgerUuid[ledger.uuid] ?? const [];
          }
        }
      }

      for (var index = 0; index < ledgers.length; index += 1) {
        ledgers[index].sortOrder =
            cachedSortOrderByRemoteUuid[ledgers[index].uuid] ??
            ledgers.length - index - 1;
        await _db.saveLedger(ledgers[index]);
      }
      final localTemporaryLedgers = await _localTemporaryLedgers(
        includeDeleted: includeDeleted,
      );
      await _refreshSyncedLocalTemporaryMetadata(
        localTemporaryLedgers,
        ledgers,
      );
      return _mergeSyncedLocalTemporaryLedgers([
        ...localTemporaryLedgers,
        ...ledgers,
      ]);
    } catch (_) {
      return getCachedLedgers(includeDeleted: includeDeleted);
    }
  }

  @override
  Future<void> saveLedger(Ledger ledger) async {
    if (ledger.isLocalOnly) {
      await _db.saveLedger(
        ledger
          ..pendingSync = false
          ..syncError = null,
      );
      return;
    }

    await _db.saveLedger(
      ledger
        ..pendingSync = true
        ..syncError = null,
    );

    if (ledger.shouldUploadToCloud) {
      unawaited(syncPendingWrites(ledgerUuid: ledger.uuid).catchError((_) {}));
      return;
    }

    unawaited(_pushRemoteLedgerUpdate(ledger));
  }

  Future<void> _pushRemoteLedgerUpdate(Ledger ledger) async {
    final data = {
      'name': ledger.name,
      'baseCurrencyCode': ledger.baseCurrencyCode,
      'exchangeRateToCny': ledger.exchangeRateToCNY,
    };
    try {
      await _apiClient.put<Ledger>(
        '/api/ledgers/${ledger.remoteSyncUuid}',
        data: data,
        idempotencyKey: _operationKey('update-ledger', ledger.remoteSyncUuid),
        fromJson: _ledgerFromJson,
      );
      await _db.saveLedger(
        ledger
          ..pendingSync = false
          ..syncError = null,
      );
    } catch (error) {
      await _db.saveLedger(ledger..syncError = error.toString());
    }
  }

  @override
  Future<CreatedLedgerWithPeople> createLedgerWithPeople(
    Ledger ledger,
    List<Person> people,
  ) async {
    for (final person in people) {
      await _db.savePerson(person);
    }
    ledger
      ..personUuids = people.map((person) => person.uuid).toList()
      ..cloudPolicy = LedgerCloudPolicy.uploadRequested
      ..pendingSync = true
      ..syncError = null;
    await _db.saveLedger(ledger);
    unawaited(syncPendingWrites(ledgerUuid: ledger.uuid).catchError((_) {}));
    return CreatedLedgerWithPeople(ledger: ledger, people: people);
  }

  Future<CreatedLedgerWithPeople> _createLedgerWithPeopleRemote(
    Ledger ledger,
    List<Person> people,
  ) async {
    final saved = await _apiClient.post<CreatedLedgerWithPeople>(
      '/api/ledgers/with-people',
      data: {
        'name': ledger.name,
        'baseCurrencyCode': ledger.baseCurrencyCode,
        'exchangeRateToCny': ledger.exchangeRateToCNY,
        'people': people.map(_personToJson).toList(),
      },
      idempotencyKey: ledger.uuid,
      fromJson: _createdLedgerWithPeopleFromJson,
    );

    return saved;
  }

  Future<void> _syncPendingLocalLedgers({String? ledgerUuid}) async {
    final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
    for (final ledger in cachedLedgers) {
      if (ledgerUuid != null && ledger.uuid != ledgerUuid) {
        continue;
      }
      await _syncPendingLocalLedger(ledger.uuid);
    }
  }

  Future<void> _syncPendingLocalLedger(String ledgerUuid) {
    final current = _pendingLocalLedgerUploads[ledgerUuid];
    if (current != null) {
      return current;
    }
    late final Future<void> sync;
    sync = _syncPendingLocalLedgerNow(ledgerUuid).whenComplete(() {
      if (identical(_pendingLocalLedgerUploads[ledgerUuid], sync)) {
        _pendingLocalLedgerUploads.remove(ledgerUuid);
      }
    });
    _pendingLocalLedgerUploads[ledgerUuid] = sync;
    return sync;
  }

  Future<void> _syncPendingLocalLedgerNow(String ledgerUuid) async {
    final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = cachedLedgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    if (ledger == null ||
        _looksLikeRemoteUuid(ledger.uuid) ||
        ledger.hasSyncedRemoteCopy ||
        !ledger.shouldUploadToCloud ||
        ledger.isDeleted) {
      return;
    }

    final cachedPeople = await _db.getAllPeople(includeDeleted: true);
    final peopleByUuid = {
      for (final person in cachedPeople) person.uuid: person,
    };
    final transactions = await _db.getTransactionsForLedger(ledger.uuid);
    final referencedPersonUuids = <String>{
      ...ledger.personUuids,
      for (final transaction in transactions) ...transaction.personUuids,
      for (final transaction in transactions)
        if (transaction.payerPersonUuid != null) transaction.payerPersonUuid!,
    };
    final people = referencedPersonUuids
        .map((uuid) => peopleByUuid[uuid])
        .whereType<Person>()
        .toList();
    final localLedgerUuid = ledger.uuid;
    final created = await _createLedgerWithPeopleRemote(ledger, people);
    final remoteLedgerUuid = created.ledger.uuid;
    ledger
      ..uuid = localLedgerUuid
      ..syncedRemoteUuid = remoteLedgerUuid
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged
      ..role = created.ledger.role
      ..memberCount = created.ledger.memberCount
      ..members = created.ledger.members
      ..pendingSync = false
      ..syncError = null;
    await _db.saveLedger(ledger);
    await _identityResolver.recordLedgerMapping(
      localUuid: localLedgerUuid,
      remoteUuid: remoteLedgerUuid,
    );
    for (var index = 0; index < people.length; index += 1) {
      if (index >= created.people.length) break;
      await _identityResolver.recordPersonMapping(
        localUuid: people[index].uuid,
        remoteUuid: created.people[index].uuid,
      );
    }
    for (final transaction in transactions) {
      await _db.saveTransaction(
        transaction
          ..clientOperationId ??= transaction.uuid
          ..pendingSync = true
          ..syncError = null,
      );
    }
  }

  Future<void> _syncPendingLedgerWrites({String? ledgerUuid}) async {
    final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
    for (final ledger in cachedLedgers) {
      if (ledgerUuid != null && ledger.uuid != ledgerUuid) {
        continue;
      }
      if (!ledger.pendingSync) {
        continue;
      }
      if (ledger.isDeleted) {
        try {
          await _deleteRemoteLedger(ledger);
        } catch (error) {
          await _db.saveLedger(ledger..syncError = error.toString());
        }
      } else {
        await _pushRemoteLedgerUpdate(ledger);
      }
    }
  }

  @override
  Future<void> syncPendingWrites({String? ledgerUuid}) async {
    await _syncPendingLocalLedgers(ledgerUuid: ledgerUuid);
    await _syncPendingLedgerWrites(ledgerUuid: ledgerUuid);
  }

  Future<List<Ledger>> _localTemporaryLedgers({
    required bool includeDeleted,
  }) async {
    final cachedLedgers = await _db.getAllLedgers(
      includeDeleted: includeDeleted,
    );
    return cachedLedgers.where((ledger) => ledger.isLocalTemporary).toList();
  }

  List<Ledger> _mergeSyncedLocalTemporaryLedgers(List<Ledger> ledgers) {
    final mergedByIdentity = <String, Ledger>{};
    final localTemporaryLedgers = ledgers
        .where((ledger) => ledger.isLocalTemporary)
        .toList();
    final cloudLedgers = ledgers
        .where((ledger) => !ledger.isLocalTemporary)
        .toList();
    for (final ledger in [...localTemporaryLedgers, ...cloudLedgers]) {
      final identity = ledger.remoteSyncUuid;
      mergedByIdentity.putIfAbsent(identity, () => ledger);
    }
    final merged = mergedByIdentity.values.toList();
    merged.sort((left, right) {
      final order = right.sortOrder.compareTo(left.sortOrder);
      if (order != 0) return order;
      if (left.isLocalTemporary == right.isLocalTemporary) return 0;
      return left.isLocalTemporary ? -1 : 1;
    });
    return merged;
  }

  Future<void> _refreshSyncedLocalTemporaryMetadata(
    List<Ledger> localTemporaryLedgers,
    List<Ledger> cloudLedgers,
  ) async {
    final cloudLedgerByUuid = {
      for (final ledger in cloudLedgers) ledger.uuid: ledger,
    };
    for (final localLedger in localTemporaryLedgers) {
      if (!localLedger.hasSyncedRemoteCopy) continue;
      final cloudLedger = cloudLedgerByUuid[localLedger.remoteSyncUuid];
      if (cloudLedger == null) continue;
      localLedger
        ..role = cloudLedger.role
        ..memberCount = cloudLedger.memberCount
        ..members = cloudLedger.members
        ..cacheOwnerUserUuid = cloudLedger.cacheOwnerUserUuid
        ..cloudPolicy = LedgerCloudPolicy.cloudManaged;
      await _db.saveLedger(localLedger);
    }
  }

  Future<List<Ledger>> _visibleCachedLedgers(List<Ledger> ledgers) async {
    final tokenStore = _tokenStore;
    if (tokenStore == null) {
      return _mergeSyncedLocalTemporaryLedgers(ledgers);
    }
    final accountUuid = await tokenStore.readAccountUuid();
    return _mergeSyncedLocalTemporaryLedgers(
      ledgers.where((ledger) {
        return ledger.isLocalTemporary ||
            ledger.cacheOwnerUserUuid == accountUuid && accountUuid != null;
      }).toList(),
    );
  }

  bool _looksLikeRemoteUuid(String uuid) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid);
  }

  String _operationKey(String prefix, String uuid) {
    return '$prefix-$uuid-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<void> deleteLedger(String uuid) async {
    await _db.deleteLedger(uuid);
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers.where((item) => item.uuid == uuid).firstOrNull;
    if (ledger == null) {
      return;
    }
    if (ledger.isLocalOnly) {
      return;
    }
    await _db.saveLedger(
      ledger
        ..pendingSync = true
        ..syncError = null,
    );
    unawaited(
      _deleteRemoteLedger(ledger).catchError(
        (error) => _db.saveLedger(ledger..syncError = error.toString()),
      ),
    );
  }

  Future<void> _deleteRemoteLedger(Ledger ledger) async {
    if (!_looksLikeRemoteUuid(ledger.remoteSyncUuid)) {
      await _db.saveLedger(
        ledger
          ..pendingSync = false
          ..syncError = null,
      );
      return;
    }
    await _apiClient.deleteVoid(
      '/api/ledgers/${ledger.remoteSyncUuid}',
      idempotencyKey: 'delete-ledger-${ledger.remoteSyncUuid}',
    );
    await _db.saveLedger(
      ledger
        ..pendingSync = false
        ..syncError = null,
    );
  }

  static Ledger _ledgerFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Ledger()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..baseCurrencyCode = map['baseCurrencyCode'].toString()
      ..exchangeRateToCNY =
          (map['exchangeRateToCny'] as num?)?.toDouble() ?? 1.0
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged
      ..role = map['role']?.toString()
      ..memberCount = (map['memberCount'] as num?)?.toInt() ?? 1
      ..members = (map['members'] as List<dynamic>? ?? [])
          .map(_memberFromJson)
          .toList();
  }

  static Map<String, dynamic> _personToJson(Person person) {
    return {
      'name': person.name,
      'avatar': person.avatar,
      'linkedUserUuid': person.linkedUserUuid,
    };
  }

  static Person _personFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Person()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..avatar = map['avatar']?.toString() ?? ''
      ..linkedUserUuid = map['linkedUserUuid']?.toString();
  }

  static CreatedLedgerWithPeople _createdLedgerWithPeopleFromJson(
    Object? json,
  ) {
    final map = json! as Map<String, dynamic>;
    final ledger = _ledgerFromJson(map['ledger']);
    final people = (map['people'] as List<dynamic>? ?? [])
        .map(_personFromJson)
        .toList();
    ledger.personUuids = people.map((person) => person.uuid).toList();
    return CreatedLedgerWithPeople(ledger: ledger, people: people);
  }

  static LedgerMemberSummary _memberFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return LedgerMemberSummary(
      uuid: map['uuid']?.toString() ?? '',
      userUuid: map['userUuid']?.toString(),
      nickname: map['nickname']?.toString(),
      avatar: map['avatar']?.toString(),
      role: map['role']?.toString(),
    );
  }

  static _LedgerPeopleBatch _ledgerPeopleBatchFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    final peopleByUuid = <String, Person>{};
    final peopleByLedgerUuid = map.map((ledgerUuid, peopleJson) {
      final people = (peopleJson as List<dynamic>)
          .map(_personFromJson)
          .toList();
      for (final person in people) {
        peopleByUuid[person.uuid] = person;
      }
      return MapEntry(ledgerUuid, people.map((person) => person.uuid).toList());
    });
    return _LedgerPeopleBatch(
      peopleByLedgerUuid: peopleByLedgerUuid,
      people: peopleByUuid.values.toList(),
    );
  }
}
