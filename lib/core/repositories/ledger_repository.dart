import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/person.dart';
import '../network/api_client.dart';

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
  const RemoteLedgerRepository({
    required ApiClient apiClient,
    required DatabaseService database,
  }) : _apiClient = apiClient,
       _db = database;

  final ApiClient _apiClient;
  final DatabaseService _db;

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    try {
      final ledgers = await _apiClient.get<List<Ledger>>(
        '/api/ledgers',
        fromJson: (json) =>
            (json! as List<dynamic>).map(_ledgerFromJson).toList(),
      );
      if (ledgers.isEmpty) {
        return ledgers;
      }
      final cachedLedgers = await _db.getAllLedgers(includeDeleted: true);
      final cachedPeopleByLedgerUuid = {
        for (final ledger in cachedLedgers) ledger.uuid: ledger.personUuids,
      };

      try {
        final peopleByLedger = await _apiClient.get<Map<String, List<String>>>(
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

      for (var index = 0; index < ledgers.length; index += 1) {
        ledgers[index].sortOrder = index;
        await _db.saveLedger(ledgers[index]);
      }
      return ledgers;
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

    if (!_looksLikeRemoteUuid(ledger.uuid)) {
      final saved = await _apiClient.post<Ledger>(
        '/api/ledgers',
        data: data,
        idempotencyKey: ledger.uuid,
        fromJson: _ledgerFromJson,
      );
      ledger
        ..uuid = saved.uuid
        ..name = saved.name
        ..baseCurrencyCode = saved.baseCurrencyCode
        ..exchangeRateToCNY = saved.exchangeRateToCNY;
      await _db.saveLedger(ledger);
      return;
    }

    await _apiClient.put<Ledger>(
      '/api/ledgers/${ledger.uuid}',
      data: data,
      idempotencyKey: _operationKey('update-ledger', ledger.uuid),
      fromJson: _ledgerFromJson,
    );
    await _db.saveLedger(ledger);
  }

  @override
  Future<CreatedLedgerWithPeople> createLedgerWithPeople(
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

    ledger
      ..uuid = saved.ledger.uuid
      ..name = saved.ledger.name
      ..baseCurrencyCode = saved.ledger.baseCurrencyCode
      ..exchangeRateToCNY = saved.ledger.exchangeRateToCNY
      ..personUuids = saved.people.map((person) => person.uuid).toList()
      ..role = saved.ledger.role
      ..memberCount = saved.ledger.memberCount
      ..members = saved.ledger.members;
    await _db.saveLedger(ledger);
    for (final person in saved.people) {
      await _db.savePerson(person);
    }
    return CreatedLedgerWithPeople(ledger: ledger, people: saved.people);
  }

  bool _looksLikeRemoteUuid(String uuid) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid);
  }

  String _operationKey(String prefix, String uuid) {
    return '$prefix-$uuid-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<void> deleteLedger(String uuid) async {
    await _apiClient.deleteVoid(
      '/api/ledgers/$uuid',
      idempotencyKey: 'delete-ledger-$uuid',
    );
    await _db.deleteLedger(uuid);
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
