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
  }) : _apiClient = apiClient,
       _ledgerRepository = ledgerRepository;

  final ApiClient _apiClient;
  final LedgerRepository _ledgerRepository;

  @override
  Future<List<Person>> getAllPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) async {
    if (ledgerUuid != null) {
      return _apiClient.get<List<Person>>(
        '/api/ledgers/$ledgerUuid/people',
        fromJson: (json) =>
            (json! as List<dynamic>).map(_personFromJson).toList(),
      );
    }

    final ledgers = await _ledgerRepository.getAllLedgers();
    final people = <Person>[];
    for (final ledger in ledgers) {
      people.addAll(
        await _apiClient.get<List<Person>>(
          '/api/ledgers/${ledger.uuid}/people',
          fromJson: (json) =>
              (json! as List<dynamic>).map(_personFromJson).toList(),
        ),
      );
    }
    return people;
  }

  @override
  Future<void> savePerson(Person person, {String? ledgerUuid}) async {
    if (ledgerUuid == null) {
      throw ArgumentError('Remote person writes require ledgerUuid.');
    }

    final data = {'name': person.name, 'avatar': person.avatar};
    if (_looksLikeRemoteUuid(person.uuid)) {
      await _apiClient.put<Person>(
        '/api/ledgers/$ledgerUuid/people/${person.uuid}',
        data: data,
        idempotencyKey: 'update-person-${person.uuid}',
        fromJson: _personFromJson,
      );
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
      ..avatar = saved.avatar;
  }

  @override
  Future<void> deletePerson(String uuid, {String? ledgerUuid}) {
    if (ledgerUuid == null) {
      throw ArgumentError('Remote person deletes require ledgerUuid.');
    }
    return _apiClient.deleteVoid(
      '/api/ledgers/$ledgerUuid/people/$uuid',
      idempotencyKey: 'delete-person-$uuid',
    );
  }

  bool _looksLikeRemoteUuid(String uuid) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid);
  }

  static Person _personFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Person()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..avatar = map['avatar']?.toString() ?? '';
  }
}
