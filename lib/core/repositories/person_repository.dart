import '../database/database_service.dart';
import '../models/person.dart';
import '../network/api_client.dart';
import 'ledger_repository.dart';

abstract class PersonRepository {
  Future<List<Person>> getAllPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  });

  Future<void> savePerson(Person person, {String? ledgerUuid});

  Future<void> deletePerson(String uuid, {String? ledgerUuid});
}

class LocalPersonRepository implements PersonRepository {
  const LocalPersonRepository(this._db);

  final DatabaseService _db;

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
}

class RemotePersonRepository implements PersonRepository {
  const RemotePersonRepository({
    required ApiClient apiClient,
    required LedgerRepository ledgerRepository,
    required DatabaseService database,
  }) : _apiClient = apiClient,
       _ledgerRepository = ledgerRepository,
       _db = database;

  final ApiClient _apiClient;
  final LedgerRepository _ledgerRepository;
  final DatabaseService _db;

  @override
  Future<List<Person>> getAllPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) async {
    if (ledgerUuid != null) {
      try {
        final people = await _apiClient.get<List<Person>>(
          '/api/ledgers/$ledgerUuid/people',
          fromJson: (json) =>
              (json! as List<dynamic>).map(_personFromJson).toList(),
        );
        for (final person in people) {
          await _db.savePerson(person);
        }
        await _cacheLedgerPeople(ledgerUuid, people);
        return people;
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
    if (ledger == null || ledger.personUuids.isEmpty) {
      return const [];
    }

    final personUuidSet = ledger.personUuids.toSet();
    final people = await _db.getAllPeople(includeDeleted: includeDeleted);
    return people
        .where((person) => personUuidSet.contains(person.uuid))
        .toList();
  }

  Future<void> _savePersonLocally(Person person) async {
    await _db.savePerson(person);
  }

  Future<void> _deletePersonLocally(String uuid) async {
    await _db.deletePerson(uuid);
  }

  Future<void> _cacheLedgerPeople(
    String ledgerUuid,
    List<Person> people,
  ) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    if (ledger == null) {
      return;
    }
    ledger.personUuids = people.map((person) => person.uuid).toList();
    await _db.saveLedger(ledger);
  }

  Future<void> _saveRemotePerson(Person person, String ledgerUuid) async {
    final data = {
      'name': person.name,
      'avatar': person.avatar,
      'linkedUserUuid': person.linkedUserUuid,
    };
    if (_looksLikeRemoteUuid(person.uuid)) {
      final saved = await _apiClient.put<Person>(
        '/api/ledgers/$ledgerUuid/people/${person.uuid}',
        data: data,
        idempotencyKey: _operationKey('update-person', person.uuid),
        fromJson: _personFromJson,
      );
      person
        ..name = saved.name
        ..avatar = saved.avatar
        ..linkedUserUuid = saved.linkedUserUuid;
      await _savePersonLocally(person);
      return;
    }

    final saved = await _apiClient.post<Person>(
      '/api/ledgers/$ledgerUuid/people',
      data: data,
      idempotencyKey: person.uuid,
      fromJson: _personFromJson,
    );
    person
      ..uuid = saved.uuid
      ..name = saved.name
      ..avatar = saved.avatar
      ..linkedUserUuid = saved.linkedUserUuid;
    await _savePersonLocally(person);
  }

  @override
  Future<void> savePerson(Person person, {String? ledgerUuid}) async {
    if (ledgerUuid == null) {
      throw ArgumentError('Remote person writes require ledgerUuid.');
    }

    await _saveRemotePerson(person, ledgerUuid);
  }

  @override
  Future<void> deletePerson(String uuid, {String? ledgerUuid}) async {
    if (ledgerUuid == null) {
      throw ArgumentError('Remote person deletes require ledgerUuid.');
    }
    await _apiClient.deleteVoid(
      '/api/ledgers/$ledgerUuid/people/$uuid',
      idempotencyKey: 'delete-person-$uuid',
    );
    await _deletePersonLocally(uuid);
  }

  bool _looksLikeRemoteUuid(String uuid) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid);
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
