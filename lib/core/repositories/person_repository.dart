import 'dart:async';

import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/person.dart';
import '../network/api_client.dart';
import '../services/sync_identity_resolver.dart';
import 'ledger_repository.dart';

abstract class PersonRepository {
  Future<List<Person>> getCachedPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  });

  Future<List<Person>> getAllPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  });

  Future<void> savePerson(Person person, {String? ledgerUuid});

  Future<void> deletePerson(String uuid, {String? ledgerUuid});

  Future<void> syncPendingPeople(String ledgerUuid);
}

class LocalPersonRepository implements PersonRepository {
  const LocalPersonRepository(this._db);

  final DatabaseService _db;

  @override
  Future<List<Person>> getCachedPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) {
    return _db.getAllPeople(includeDeleted: includeDeleted);
  }

  @override
  Future<List<Person>> getAllPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) {
    return _db.getAllPeople(includeDeleted: includeDeleted);
  }

  @override
  Future<void> savePerson(Person person, {String? ledgerUuid}) {
    return _db.savePerson(person);
  }

  @override
  Future<void> deletePerson(String uuid, {String? ledgerUuid}) {
    return _db.deletePerson(uuid);
  }

  @override
  Future<void> syncPendingPeople(String ledgerUuid) async {}
}

class RemotePersonRepository implements PersonRepository {
  RemotePersonRepository({
    required ApiClient apiClient,
    required LedgerRepository ledgerRepository,
    required DatabaseService database,
    SyncIdentityResolver? identityResolver,
  }) : _apiClient = apiClient,
       _ledgerRepository = ledgerRepository,
       _db = database,
       _identityResolver = identityResolver ?? SyncIdentityResolver(database);

  final ApiClient _apiClient;
  final LedgerRepository _ledgerRepository;
  final DatabaseService _db;
  final SyncIdentityResolver _identityResolver;

  @override
  Future<List<Person>> getCachedPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) {
    if (ledgerUuid == null) {
      return _db.getAllPeople(includeDeleted: includeDeleted);
    }
    return _cachedPeopleForLedger(ledgerUuid, includeDeleted: includeDeleted);
  }

  @override
  Future<List<Person>> getAllPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) async {
    if (ledgerUuid != null) {
      if (await _isLocalOnlyLedger(ledgerUuid)) {
        return _cachedPeopleForLedger(
          ledgerUuid,
          includeDeleted: includeDeleted,
        );
      }
      try {
        await syncPendingPeople(ledgerUuid);
        final remoteLedgerUuid = await _identityResolver.resolveLedgerUuid(
          ledgerUuid,
        );
        final cachedPersonUuidsBeforeRefresh = await _ledgerPersonUuids(
          ledgerUuid,
        );
        final people = await _apiClient.get<List<Person>>(
          '/api/ledgers/$remoteLedgerUuid/people',
          fromJson: (json) =>
              (json! as List<dynamic>).map(_personFromJson).toList(),
        );
        for (final person in people) {
          await _db.savePerson(person);
        }
        await _cacheLedgerPeople(
          ledgerUuid,
          people,
          cachedPersonUuidsBeforeRefresh: cachedPersonUuidsBeforeRefresh,
        );
        return _mergeCachedPeople(
          ledgerUuid,
          people,
          includeDeleted: includeDeleted,
        );
      } catch (_) {
        return _cachedPeopleForLedger(
          ledgerUuid,
          includeDeleted: includeDeleted,
        );
      }
    }

    try {
      final ledgers = await _ledgerRepository.getAllLedgers();
      final people = <Person>[];
      for (final ledger in ledgers) {
        people.addAll(
          await getAllPeople(
            includeDeleted: includeDeleted,
            ledgerUuid: ledger.uuid,
          ),
        );
      }
      return people;
    } catch (_) {
      return _db.getAllPeople(includeDeleted: includeDeleted);
    }
  }

  Future<List<Person>> _cachedPeopleForLedger(
    String ledgerUuid, {
    required bool includeDeleted,
  }) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    if (ledger == null) {
      return const [];
    }

    final personUuidSet = await _cachedPersonUuidsForLedger(
      ledger,
      includeDeleted: includeDeleted,
    );
    if (personUuidSet.isEmpty) {
      return const [];
    }

    final people = await _db.getAllPeople(includeDeleted: includeDeleted);
    return people
        .where((person) => personUuidSet.contains(person.uuid))
        .toList();
  }

  Future<List<Person>> _mergeCachedPeople(
    String ledgerUuid,
    List<Person> remotePeople, {
    required bool includeDeleted,
  }) async {
    final cachedPeople = await _cachedPeopleForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );
    return {
      for (final person in remotePeople) person.uuid: person,
      for (final person in cachedPeople) person.uuid: person,
    }.values.toList();
  }

  Future<Set<String>> _cachedPersonUuidsForLedger(
    Ledger ledger, {
    required bool includeDeleted,
  }) async {
    final personUuids = ledger.personUuids.toSet();
    if (!includeDeleted) {
      return personUuids;
    }

    final transactions = await _db.getTransactionsForLedger(
      ledger.uuid,
      includeDeleted: true,
    );
    for (final transaction in transactions) {
      personUuids.addAll(transaction.personUuids);
      final payerPersonUuid = transaction.payerPersonUuid;
      if (payerPersonUuid != null && payerPersonUuid.isNotEmpty) {
        personUuids.add(payerPersonUuid);
      }
    }
    return personUuids;
  }

  Future<void> _savePersonLocally(Person person) async {
    await _db.savePerson(person);
  }

  Future<void> _deletePersonLocally(String uuid) async {
    await _db.deletePerson(uuid);
  }

  Future<void> _cacheLedgerPeople(
    String ledgerUuid,
    List<Person> remotePeople, {
    required Set<String> cachedPersonUuidsBeforeRefresh,
  }) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    if (ledger == null) {
      return;
    }
    final activePeople = await _db.getAllPeople();
    final activePersonUuids = activePeople.map((person) => person.uuid).toSet();
    final localPersonUuidsAddedDuringRefresh = ledger.personUuids
        .where((uuid) => !cachedPersonUuidsBeforeRefresh.contains(uuid))
        .where(activePersonUuids.contains);
    final pendingPersonUuids = activePeople
        .where(
          (person) =>
              person.pendingSync && person.pendingLedgerUuid == ledgerUuid,
        )
        .map((person) => person.uuid);
    ledger.personUuids = {
      ...remotePeople.map((person) => person.uuid),
      ...localPersonUuidsAddedDuringRefresh,
      ...pendingPersonUuids,
    }.toList();
    await _db.saveLedger(ledger);
  }

  Future<Set<String>> _ledgerPersonUuids(String ledgerUuid) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    return ledger?.personUuids.toSet() ?? const {};
  }

  Future<void> _saveRemotePerson(Person person, String ledgerUuid) async {
    if (await _isLocalOnlyLedger(ledgerUuid)) {
      await _savePersonLocally(
        person
          ..pendingSync = false
          ..syncError = null
          ..pendingLedgerUuid = null,
      );
      return;
    }
    await _savePersonLocally(
      person
        ..pendingSync = true
        ..syncError = null
        ..pendingLedgerUuid = ledgerUuid,
    );

    final remoteLedgerUuid = await _identityResolver.resolveLedgerUuid(
      ledgerUuid,
    );
    if (!_looksLikeRemoteUuid(remoteLedgerUuid)) {
      return;
    }

    final data = {
      'name': person.name,
      'avatar': person.avatar,
      'linkedUserUuid': person.linkedUserUuid,
    };
    try {
      final remotePersonUuid = await _identityResolver.resolvePersonUuid(
        person.uuid,
      );
      if (_looksLikeRemoteUuid(remotePersonUuid)) {
        final saved = await _apiClient.put<Person>(
          '/api/ledgers/$remoteLedgerUuid/people/$remotePersonUuid',
          data: data,
          idempotencyKey: _operationKey('update-person', remotePersonUuid),
          fromJson: _personFromJson,
        );
        person
          ..name = saved.name
          ..avatar = saved.avatar
          ..linkedUserUuid = saved.linkedUserUuid
          ..pendingSync = false
          ..syncError = null
          ..pendingLedgerUuid = null;
        await _savePersonLocally(person);
        return;
      }

      final saved = await _apiClient.post<Person>(
        '/api/ledgers/$remoteLedgerUuid/people',
        data: data,
        idempotencyKey: person.uuid,
        fromJson: _personFromJson,
      );
      final localUuid = person.uuid;
      await _identityResolver.recordPersonMapping(
        localUuid: localUuid,
        remoteUuid: saved.uuid,
      );
      person
        ..uuid = saved.uuid
        ..name = saved.name
        ..avatar = saved.avatar
        ..linkedUserUuid = saved.linkedUserUuid
        ..pendingSync = false
        ..syncError = null
        ..pendingLedgerUuid = null;
      await _savePersonLocally(person);
      await _db.replacePersonUuidReferences(
        oldUuid: localUuid,
        newUuid: saved.uuid,
      );
    } catch (error) {
      await _savePersonLocally(person..syncError = error.toString());
    }
  }

  @override
  Future<void> savePerson(Person person, {String? ledgerUuid}) async {
    if (ledgerUuid == null) {
      throw ArgumentError('Remote person writes require ledgerUuid.');
    }

    if (await _isLocalOnlyLedger(ledgerUuid)) {
      await _savePersonLocally(
        person
          ..pendingSync = false
          ..syncError = null
          ..pendingLedgerUuid = null,
      );
      await _attachPersonToLedger(ledgerUuid, person.uuid);
      return;
    }
    await _savePersonLocally(
      person
        ..pendingSync = true
        ..syncError = null
        ..pendingLedgerUuid = ledgerUuid,
    );
    await _attachPersonToLedger(ledgerUuid, person.uuid);
    unawaited(_saveRemotePerson(person, ledgerUuid));
  }

  @override
  Future<void> deletePerson(String uuid, {String? ledgerUuid}) async {
    if (ledgerUuid == null) {
      throw ArgumentError('Remote person deletes require ledgerUuid.');
    }
    await _deletePersonLocally(uuid);
    if (await _isLocalOnlyLedger(ledgerUuid)) {
      return;
    }
    final people = await _db.getAllPeople(includeDeleted: true);
    final person = people.where((item) => item.uuid == uuid).firstOrNull;
    if (person == null) return;
    person
      ..pendingSync = true
      ..syncError = null
      ..pendingLedgerUuid = ledgerUuid;
    await _savePersonLocally(person);
    final remoteLedgerUuid = await _identityResolver.resolveLedgerUuid(
      ledgerUuid,
    );
    final remotePersonUuid = await _identityResolver.resolvePersonUuid(uuid);
    if (!_looksLikeRemoteUuid(remoteLedgerUuid) ||
        !_looksLikeRemoteUuid(remotePersonUuid)) {
      return;
    }
    unawaited(
      _deleteRemotePerson(person, ledgerUuid).catchError(
        (error) => _savePersonLocally(person..syncError = error.toString()),
      ),
    );
  }

  @override
  Future<void> syncPendingPeople(String ledgerUuid) async {
    if (await _isLocalOnlyLedger(ledgerUuid)) {
      return;
    }
    final people = await _db.getAllPeople(includeDeleted: true);
    final pending = people.where((person) {
      return person.pendingSync && person.pendingLedgerUuid == ledgerUuid;
    });
    for (final person in pending) {
      if (person.isDeleted) {
        await _deleteRemotePerson(person, ledgerUuid);
        continue;
      }
      await _saveRemotePerson(person, ledgerUuid);
    }
  }

  Future<void> _deleteRemotePerson(Person person, String ledgerUuid) async {
    final remoteLedgerUuid = await _identityResolver.resolveLedgerUuid(
      ledgerUuid,
    );
    final remotePersonUuid = await _identityResolver.resolvePersonUuid(
      person.uuid,
    );
    if (!_looksLikeRemoteUuid(remoteLedgerUuid) ||
        !_looksLikeRemoteUuid(remotePersonUuid)) {
      return;
    }
    await _apiClient.deleteVoid(
      '/api/ledgers/$remoteLedgerUuid/people/$remotePersonUuid',
      idempotencyKey: 'delete-person-$remotePersonUuid',
    );
    person
      ..pendingSync = false
      ..syncError = null
      ..pendingLedgerUuid = null;
    await _savePersonLocally(person);
  }

  bool _looksLikeRemoteUuid(String uuid) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid);
  }

  Future<bool> _isLocalOnlyLedger(String ledgerUuid) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    return ledger?.isLocalOnly == true;
  }

  Future<void> _attachPersonToLedger(
    String ledgerUuid,
    String personUuid,
  ) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    if (ledger == null || ledger.personUuids.contains(personUuid)) {
      return;
    }
    ledger.personUuids = [...ledger.personUuids, personUuid];
    await _db.saveLedger(ledger);
  }

  String _operationKey(String prefix, String uuid) {
    return '$prefix-$uuid-${DateTime.now().microsecondsSinceEpoch}';
  }

  static Person _personFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Person()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..avatar = map['avatar']?.toString() ?? ''
      ..linkedUserUuid = map['linkedUserUuid']?.toString();
  }
}
