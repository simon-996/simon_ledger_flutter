import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/person.dart';
import '../network/api_client.dart';
import '../services/sync_identity_resolver.dart';

class CreatedLedgerWithPeople {
  const CreatedLedgerWithPeople({required this.ledger, required this.people});

  final Ledger ledger;
  final List<Person> people;
}

abstract class LedgerRepository {
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false});

  Future<void> saveLedger(Ledger ledger);

  Future<CreatedLedgerWithPeople> createLedgerWithPeople(
    Ledger ledger,
    List<Person> people,
  );

  Future<void> deleteLedger(String uuid);
}

class LocalLedgerRepository implements LedgerRepository {
  const LocalLedgerRepository(this._db);

  final DatabaseService _db;

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) {
    return _db.getAllLedgers(includeDeleted: includeDeleted);
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
}

class RemoteLedgerRepository implements LedgerRepository {
  RemoteLedgerRepository({
    required ApiClient apiClient,
    required DatabaseService database,
    SyncIdentityResolver? identityResolver,
  }) : _apiClient = apiClient,
       _db = database,
       _identityResolver = identityResolver ?? SyncIdentityResolver(database);

  final ApiClient _apiClient;
  final DatabaseService _db;
  final SyncIdentityResolver _identityResolver;

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    try {
      await _syncPendingLocalLedgers();
      await _syncPendingLedgerWrites();
      final ledgers = await _apiClient.get<List<Ledger>>(
        '/api/ledgers',
        fromJson: (json) =>
            (json! as List<dynamic>).map(_ledgerFromJson).toList(),
      );
      final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
      final cachedPeopleByLedgerUuid = {
        for (final ledger in cachedLedgers) ledger.uuid: ledger.personUuids,
      };

      if (ledgers.isNotEmpty) {
        try {
          final peopleByLedger = await _apiClient
              .get<Map<String, List<String>>>(
                '/api/ledgers/people',
                queryParameters: {
                  'ledgerUuids': ledgers.map((ledger) => ledger.uuid).join(','),
                },
                fromJson: _peopleByLedgerFromJson,
              );
          for (final ledger in ledgers) {
            ledger.personUuids = peopleByLedger[ledger.uuid] ?? const [];
          }
        } catch (_) {
          for (final ledger in ledgers) {
            ledger.personUuids =
                cachedPeopleByLedgerUuid[ledger.uuid] ?? const [];
          }
        }
      }

      for (var index = 0; index < ledgers.length; index += 1) {
        ledgers[index].sortOrder = index;
        await _db.saveLedger(ledgers[index]);
      }
      final localTemporaryLedgers = await _localTemporaryLedgers(
        includeDeleted: includeDeleted,
      );
      return [...localTemporaryLedgers, ...ledgers];
    } catch (_) {
      return _db.getAllLedgers(includeDeleted: includeDeleted);
    }
  }

  @override
  Future<void> saveLedger(Ledger ledger) async {
    final data = {
      'name': ledger.name,
      'baseCurrencyCode': ledger.baseCurrencyCode,
      'exchangeRateToCny': ledger.exchangeRateToCNY,
    };

    await _db.saveLedger(
      ledger
        ..pendingSync = true
        ..syncError = null,
    );

    if (!ledger.hasSyncedRemoteCopy && !_looksLikeRemoteUuid(ledger.uuid)) {
      try {
        final saved = await _apiClient.post<Ledger>(
          '/api/ledgers',
          data: data,
          idempotencyKey: ledger.uuid,
          fromJson: _ledgerFromJson,
        );
        ledger
          ..syncedRemoteUuid = saved.uuid
          ..name = saved.name
          ..baseCurrencyCode = saved.baseCurrencyCode
          ..exchangeRateToCNY = saved.exchangeRateToCNY
          ..pendingSync = false
          ..syncError = null;
        await _db.saveLedger(ledger);
      } catch (error) {
        await _db.saveLedger(ledger..syncError = error.toString());
      }
      return;
    }

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
    try {
      return await _createLedgerWithPeopleRemote(ledger, people);
    } catch (_) {
      for (final person in people) {
        await _db.savePerson(person);
      }
      ledger.personUuids = people.map((person) => person.uuid).toList();
      await _db.saveLedger(ledger);
      return CreatedLedgerWithPeople(ledger: ledger, people: people);
    }
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

    final remoteLedger = ledger
      ..uuid = saved.ledger.uuid
      ..name = saved.ledger.name
      ..baseCurrencyCode = saved.ledger.baseCurrencyCode
      ..exchangeRateToCNY = saved.ledger.exchangeRateToCNY
      ..personUuids = saved.people.map((person) => person.uuid).toList()
      ..role = saved.ledger.role
      ..memberCount = saved.ledger.memberCount
      ..members = saved.ledger.members;
    await _db.saveLedger(remoteLedger);
    for (final person in saved.people) {
      await _db.savePerson(person);
    }
    return CreatedLedgerWithPeople(ledger: remoteLedger, people: saved.people);
  }

  Future<void> _syncPendingLocalLedgers() async {
    final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
    final cachedPeople = await _db.getAllPeople(includeDeleted: false);
    final peopleByUuid = {
      for (final person in cachedPeople) person.uuid: person,
    };
    for (final ledger in cachedLedgers) {
      if (_looksLikeRemoteUuid(ledger.uuid) ||
          ledger.hasSyncedRemoteCopy ||
          ledger.isDeleted) {
        continue;
      }

      final people = ledger.personUuids
          .map((uuid) => peopleByUuid[uuid])
          .whereType<Person>()
          .toList();
      final localLedgerUuid = ledger.uuid;
      final created = await _createLedgerWithPeopleRemote(ledger, people);
      final remoteLedgerUuid = created.ledger.uuid;
      ledger
        ..uuid = localLedgerUuid
        ..syncedRemoteUuid = remoteLedgerUuid
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
    }
  }

  Future<void> _syncPendingLedgerWrites() async {
    final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
    for (final ledger in cachedLedgers) {
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
        await saveLedger(ledger);
      }
    }
  }

  Future<List<Ledger>> _localTemporaryLedgers({
    required bool includeDeleted,
  }) async {
    final cachedLedgers = await _db.getAllLedgers(
      includeDeleted: includeDeleted,
    );
    return cachedLedgers.where((ledger) => ledger.isLocalTemporary).toList();
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
    await _db.saveLedger(
      ledger
        ..pendingSync = true
        ..syncError = null,
    );
    try {
      await _deleteRemoteLedger(ledger);
    } catch (error) {
      await _db.saveLedger(ledger..syncError = error.toString());
    }
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

  static Map<String, List<String>> _peopleByLedgerFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return map.map((ledgerUuid, peopleJson) {
      final personUuids = (peopleJson as List<dynamic>)
          .map((person) => (person as Map<String, dynamic>)['uuid'].toString())
          .toList();
      return MapEntry(ledgerUuid, personUuids);
    });
  }
}
