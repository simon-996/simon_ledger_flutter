import '../database/database_service.dart';
import '../models/person.dart';
import '../network/api_client.dart';
import 'ledger_repository.dart';

abstract class PersonRepository {
  Future<List<Person>> getAllPeople({bool includeDeleted = false});

  Future<void> savePerson(Person person);

  Future<void> deletePerson(String uuid);
}

class LocalPersonRepository implements PersonRepository {
  const LocalPersonRepository(this._db);

  final DatabaseService _db;

  @override
  Future<List<Person>> getAllPeople({bool includeDeleted = false}) {
    return _db.getAllPeople(includeDeleted: includeDeleted);
  }

  @override
  Future<void> savePerson(Person person) {
    return _db.savePerson(person);
  }

  @override
  Future<void> deletePerson(String uuid) {
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
  Future<List<Person>> getAllPeople({bool includeDeleted = false}) async {
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
  Future<void> savePerson(Person person) {
    throw UnsupportedError(
      'Remote person writes require a ledger-scoped person workflow.',
    );
  }

  @override
  Future<void> deletePerson(String uuid) {
    throw UnsupportedError(
      'Remote person deletes require a ledger-scoped person workflow.',
    );
  }

  static Person _personFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Person()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..avatar = map['avatar']?.toString() ?? '';
  }
}
