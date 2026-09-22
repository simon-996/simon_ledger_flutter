import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_data_scope.dart';
import '../models/ledger.dart';
import '../models/local_profile.dart';
import '../models/person.dart';
import '../models/transaction_record.dart';
import '../preferences/local_profile_store.dart';

class DatabaseService {
  static const _legacyPeopleKey = 'local_store.people.v1';
  static const _legacyLedgersKey = 'local_store.ledgers.v1';
  static const _legacyTransactionsKey = 'local_store.transactions.v1';
  static const _migrationKey = 'local_store.scope_migration.v2';

  DatabaseService({this.scope = const LocalDataScope.guest()});

  final LocalDataScope scope;
  Future<void>? _migrationFuture;

  Future<void> init() async {
    await _ensureReady();
    if (!scope.isGuest) return;

    final profile = await const LocalProfileStore().read();
    final people = await _readPeople();
    if (people.isEmpty) {
      await _writePeople([
        Person()
          ..id = 1
          ..uuid = 'self'
          ..name = profile.normalizedNickname
          ..avatar = profile.personAvatar,
      ]);
      return;
    }
    await _syncLocalSelfPerson(people, profile);
  }

  Future<void> _ensureReady() {
    return _migrationFuture ??= _migrateLegacyStore();
  }

  Future<void> _migrateLegacyStore() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationKey) != true) {
      final oldLedgers = (await _readJsonList(
        _legacyLedgersKey,
      )).map(_ledgerFromJson).toList();
      final oldPeople = (await _readJsonList(
        _legacyPeopleKey,
      )).map(_personFromJson).toList();
      final oldTransactions = (await _readJsonList(
        _legacyTransactionsKey,
      )).map(_transactionFromJson).toList();

      final ledgerByUuid = {
        for (final ledger in oldLedgers) ledger.uuid: ledger,
      };
      for (final ledger in oldLedgers) {
        final owner = ledger.cacheOwnerUserUuid?.trim();
        ledger.localAccountUuid = owner == null || owner.isEmpty ? null : owner;
        if (ledger.localAccountUuid == null && ledger.isCloudManaged) {
          ledger.isDeleted = true;
        }
      }

      final peopleByLedgerUuid = <String, String?>{};
      for (final ledger in oldLedgers) {
        for (final personUuid in ledger.personUuids) {
          final previous = peopleByLedgerUuid[personUuid];
          final current = ledger.localAccountUuid;
          if (!peopleByLedgerUuid.containsKey(personUuid) ||
              previous == current) {
            peopleByLedgerUuid[personUuid] = current;
          } else {
            peopleByLedgerUuid[personUuid] = null;
          }
        }
      }
      for (final person in oldPeople) {
        person.localAccountUuid = peopleByLedgerUuid[person.uuid];
      }
      for (final transaction in oldTransactions) {
        transaction.localAccountUuid =
            ledgerByUuid[transaction.ledgerUuid]?.localAccountUuid;
      }

      await _writeMigratedLedgers(oldLedgers);
      await _writeMigratedPeople(oldPeople);
      await _writeMigratedTransactions(oldTransactions);
      await prefs.setBool(_migrationKey, true);
      await prefs.remove(_legacyPeopleKey);
      await prefs.remove(_legacyLedgersKey);
      await prefs.remove(_legacyTransactionsKey);
    }
  }

  Future<void> _writeMigratedLedgers(List<Ledger> ledgers) async {
    final byScope = <String, List<Ledger>>{};
    for (final ledger in ledgers) {
      byScope
          .putIfAbsent(_scopeKey(ledger.localAccountUuid), () => [])
          .add(ledger);
    }
    for (final entry in byScope.entries) {
      await _writeJsonList(
        'local_store.${entry.key}.ledgers.v2',
        entry.value.map(_ledgerToJson).toList(),
      );
    }
  }

  Future<void> _writeMigratedPeople(List<Person> people) async {
    final byScope = <String, List<Person>>{};
    for (final person in people) {
      byScope
          .putIfAbsent(_scopeKey(person.localAccountUuid), () => [])
          .add(person);
    }
    for (final entry in byScope.entries) {
      await _writeJsonList(
        'local_store.${entry.key}.people.v2',
        entry.value.map(_personToJson).toList(),
      );
    }
  }

  Future<void> _writeMigratedTransactions(
    List<TransactionRecord> transactions,
  ) async {
    final byScope = <String, List<TransactionRecord>>{};
    for (final transaction in transactions) {
      byScope
          .putIfAbsent(_scopeKey(transaction.localAccountUuid), () => [])
          .add(transaction);
    }
    for (final entry in byScope.entries) {
      await _writeJsonList(
        'local_store.${entry.key}.transactions.v2',
        entry.value.map(_transactionToJson).toList(),
      );
    }
  }

  String _scopeKey(String? accountUuid) {
    return accountUuid == null || accountUuid.isEmpty
        ? 'guest'
        : 'account.$accountUuid';
  }

  Future<void> _syncLocalSelfPerson(
    List<Person> people,
    LocalProfile profile,
  ) async {
    var changed = false;
    for (final person in people) {
      if (person.uuid != 'self' && person.uuid != 'p1') continue;
      final name = profile.normalizedNickname;
      final avatar = profile.personAvatar;
      if (person.name == name && person.avatar == avatar) continue;
      person
        ..name = name
        ..avatar = avatar;
      changed = true;
    }
    if (changed) await _writePeople(people);
  }

  // Person operations
  Future<List<Person>> getAllPeople({bool includeDeleted = false}) async {
    await _ensureReady();
    final people = await _visiblePeople();
    if (includeDeleted) return people;
    return people.where((person) => !person.isDeleted).toList();
  }

  Future<void> savePerson(Person person) async {
    await _ensureReady();
    final target = await _personTargetScope(person);
    final people = await _readPeopleForScope(target);
    _upsertByUuid<Person>(
      people,
      person,
      uuidOf: (value) => value.uuid,
      assignId: (value) => value.id = _nextId(people.map((item) => item.id)),
    );
    await _writePeopleForScope(target, people);
  }

  Future<void> deletePerson(String uuid) async {
    await _ensureReady();
    final found = await _findPersonWithScope(uuid);
    if (found == null) return;
    found.value.isDeleted = true;
    await _writePeopleForScope(found.key, await _readPeopleForScope(found.key));
  }

  Future<void> replacePersonUuidReferences({
    required String oldUuid,
    required String newUuid,
  }) async {
    await _ensureReady();
    if (oldUuid == newUuid) return;

    for (final target in _visibleScopes()) {
      final people = await _readPeopleForScope(target);
      final oldIndex = people.indexWhere((person) => person.uuid == oldUuid);
      final newIndex = people.indexWhere((person) => person.uuid == newUuid);
      if (oldIndex != -1 && newIndex != -1) {
        people.removeAt(oldIndex);
      } else if (oldIndex != -1) {
        people[oldIndex].uuid = newUuid;
      }
      await _writePeopleForScope(target, people);

      final ledgers = await _readLedgersForScope(target);
      var ledgersChanged = false;
      for (final ledger in ledgers) {
        if (!ledger.personUuids.contains(oldUuid)) continue;
        ledger.personUuids = ledger.personUuids
            .map((uuid) => uuid == oldUuid ? newUuid : uuid)
            .toSet()
            .toList();
        ledgersChanged = true;
      }
      if (ledgersChanged) await _writeLedgersForScope(target, ledgers);

      final transactions = await _readTransactionsForScope(target);
      var transactionsChanged = false;
      for (final transaction in transactions) {
        if (transaction.personUuids.contains(oldUuid)) {
          transaction.personUuids = transaction.personUuids
              .map((uuid) => uuid == oldUuid ? newUuid : uuid)
              .toSet()
              .toList();
          transactionsChanged = true;
        }
        if (transaction.payerPersonUuid == oldUuid) {
          transaction.payerPersonUuid = newUuid;
          transactionsChanged = true;
        }
      }
      if (transactionsChanged) {
        await _writeTransactionsForScope(target, transactions);
      }
    }
  }

  // Ledger operations
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    await _ensureReady();
    final ledgers = await _visibleLedgers();
    final visible = includeDeleted
        ? ledgers
        : ledgers.where((ledger) => !ledger.isDeleted).toList();
    visible.sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    return visible;
  }

  Future<void> saveLedger(Ledger ledger) async {
    await _ensureReady();
    final target = await _ledgerTargetScope(ledger);
    final ledgers = await _readLedgersForScope(target);
    _upsertByUuid<Ledger>(
      ledgers,
      ledger,
      uuidOf: (value) => value.uuid,
      assignId: (value) => value.id = _nextId(ledgers.map((item) => item.id)),
    );
    await _writeLedgersForScope(target, ledgers);
  }

  Future<void> claimLedger(String uuid, String accountUuid) async {
    await _ensureReady();
    final guestScope = const LocalDataScope.guest();
    final accountScope = LocalDataScope.account(accountUuid);
    final guestLedgers = await _readLedgersForScope(guestScope);
    final ledger = guestLedgers.where((item) => item.uuid == uuid).firstOrNull;
    if (ledger == null) return;

    final guestPeople = await _readPeopleForScope(guestScope);
    final guestTransactions = await _readTransactionsForScope(guestScope);
    final personUuids = <String>{
      ...ledger.personUuids,
      for (final transaction in guestTransactions)
        if (transaction.ledgerUuid == uuid) ...transaction.personUuids,
      for (final transaction in guestTransactions)
        if (transaction.ledgerUuid == uuid &&
            transaction.payerPersonUuid != null)
          transaction.payerPersonUuid!,
    };
    final people = guestPeople
        .where((person) => personUuids.contains(person.uuid))
        .map((person) => person..localAccountUuid = accountUuid)
        .toList();
    final transactions = guestTransactions
        .where((transaction) => transaction.ledgerUuid == uuid)
        .map((transaction) => transaction..localAccountUuid = accountUuid)
        .toList();
    final claimedLedger = ledger
      ..localAccountUuid = accountUuid
      ..claimPending = true;

    final accountLedgers = await _readLedgersForScope(accountScope);
    _upsertByUuid<Ledger>(
      accountLedgers,
      claimedLedger,
      uuidOf: (value) => value.uuid,
      assignId: (value) =>
          value.id = _nextId(accountLedgers.map((item) => item.id)),
    );
    await _writeLedgersForScope(accountScope, accountLedgers);

    final accountPeople = await _readPeopleForScope(accountScope);
    for (final person in people) {
      _upsertByUuid<Person>(
        accountPeople,
        person,
        uuidOf: (value) => value.uuid,
        assignId: (value) =>
            value.id = _nextId(accountPeople.map((item) => item.id)),
      );
    }
    await _writePeopleForScope(accountScope, accountPeople);

    final accountTransactions = await _readTransactionsForScope(accountScope);
    for (final transaction in transactions) {
      _upsertByUuid<TransactionRecord>(
        accountTransactions,
        transaction,
        uuidOf: (value) => value.uuid,
        assignId: (value) =>
            value.id = _nextId(accountTransactions.map((item) => item.id)),
      );
    }
    await _writeTransactionsForScope(accountScope, accountTransactions);

    guestLedgers.removeWhere((item) => item.uuid == uuid);
    guestTransactions.removeWhere((item) => item.ledgerUuid == uuid);
    final referencedByOtherGuestLedger = <String>{
      for (final item in guestLedgers) ...item.personUuids,
      for (final item in guestTransactions) ...item.personUuids,
      for (final item in guestTransactions)
        if (item.payerPersonUuid != null) item.payerPersonUuid!,
    };
    guestPeople.removeWhere(
      (person) =>
          personUuids.contains(person.uuid) &&
          !referencedByOtherGuestLedger.contains(person.uuid),
    );
    await _writeLedgersForScope(guestScope, guestLedgers);
    await _writePeopleForScope(guestScope, guestPeople);
    await _writeTransactionsForScope(guestScope, guestTransactions);
  }

  Future<void> releaseLedgerClaim(String uuid) async {
    await _ensureReady();
    if (!scope.isAccount) return;
    final accountScope = scope;
    final accountLedgers = await _readLedgersForScope(accountScope);
    final ledger = accountLedgers
        .where((item) => item.uuid == uuid)
        .firstOrNull;
    if (ledger == null || !ledger.claimPending) return;
    final guestScope = const LocalDataScope.guest();
    final accountPeople = await _readPeopleForScope(accountScope);
    final accountTransactions = await _readTransactionsForScope(accountScope);
    final guestLedgers = await _readLedgersForScope(guestScope);
    final guestPeople = await _readPeopleForScope(guestScope);
    final guestTransactions = await _readTransactionsForScope(guestScope);

    ledger
      ..localAccountUuid = null
      ..claimPending = false
      ..cloudPolicy = LedgerCloudPolicy.localOnly
      ..pendingSync = false
      ..syncError = null;
    _upsertByUuid<Ledger>(
      guestLedgers,
      ledger,
      uuidOf: (value) => value.uuid,
      assignId: (value) =>
          value.id = _nextId(guestLedgers.map((item) => item.id)),
    );
    for (final transaction in accountTransactions.where(
      (item) => item.ledgerUuid == uuid,
    )) {
      transaction.localAccountUuid = null;
      _upsertByUuid<TransactionRecord>(
        guestTransactions,
        transaction,
        uuidOf: (value) => value.uuid,
        assignId: (value) =>
            value.id = _nextId(guestTransactions.map((item) => item.id)),
      );
    }
    for (final personUuid in ledger.personUuids) {
      final person = accountPeople
          .where((item) => item.uuid == personUuid)
          .firstOrNull;
      if (person == null) continue;
      person.localAccountUuid = null;
      _upsertByUuid<Person>(
        guestPeople,
        person,
        uuidOf: (value) => value.uuid,
        assignId: (value) =>
            value.id = _nextId(guestPeople.map((item) => item.id)),
      );
    }
    accountLedgers.removeWhere((item) => item.uuid == uuid);
    accountTransactions.removeWhere((item) => item.ledgerUuid == uuid);
    accountPeople.removeWhere((item) => ledger.personUuids.contains(item.uuid));
    await _writeLedgersForScope(accountScope, accountLedgers);
    await _writePeopleForScope(accountScope, accountPeople);
    await _writeTransactionsForScope(accountScope, accountTransactions);
    await _writeLedgersForScope(guestScope, guestLedgers);
    await _writePeopleForScope(guestScope, guestPeople);
    await _writeTransactionsForScope(guestScope, guestTransactions);
  }

  Future<void> deleteLedger(String uuid) async {
    await _ensureReady();
    final found = await _findLedgerWithScope(uuid);
    if (found == null) return;
    final ledgers = await _readLedgersForScope(found.key);
    final ledger = ledgers
        .where((item) => item.uuid == found.value.uuid)
        .firstOrNull;
    if (ledger == null) return;
    ledger.isDeleted = true;
    await _writeLedgersForScope(found.key, ledgers);

    final transactions = await _readTransactionsForScope(found.key);
    var changed = false;
    for (final transaction in transactions) {
      if (transaction.ledgerUuid == ledger.uuid && !transaction.isDeleted) {
        transaction.isDeleted = true;
        changed = true;
      }
    }
    if (changed) await _writeTransactionsForScope(found.key, transactions);
  }

  Future<void> hideLedger(String uuid) async {
    await _ensureReady();
    final found = await _findLedgerWithScope(uuid);
    if (found == null) return;
    final ledgers = await _readLedgersForScope(found.key);
    final ledger = ledgers
        .where((item) => item.uuid == uuid || item.syncedRemoteUuid == uuid)
        .firstOrNull;
    if (ledger == null) return;
    ledger.isDeleted = true;
    await _writeLedgersForScope(found.key, ledgers);
  }

  Future<void> restoreLedgerAccess(String uuid) async {
    await _ensureReady();
    final found = await _findLedgerWithScope(uuid);
    if (found == null) return;
    final ledgers = await _readLedgersForScope(found.key);
    final ledger = ledgers
        .where((item) => item.uuid == uuid || item.syncedRemoteUuid == uuid)
        .firstOrNull;
    if (ledger == null) return;
    ledger
      ..isDeleted = false
      ..pendingSync = false
      ..syncError = null;
    await _writeLedgersForScope(found.key, ledgers);
  }

  // Transaction operations
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) async {
    await _ensureReady();
    final ledger = await _findLedgerWithScope(ledgerUuid);
    final transactions = ledger == null
        ? await _visibleTransactions()
        : await _readTransactionsForScope(ledger.key);
    final visible = transactions.where((transaction) {
      if (transaction.ledgerUuid != ledgerUuid) return false;
      return includeDeleted || !transaction.isDeleted;
    }).toList();
    visible.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return visible;
  }

  Future<List<TransactionRecord>> getTransactionsForLedgers(
    List<String> ledgerUuids, {
    bool includeDeleted = false,
  }) async {
    if (ledgerUuids.isEmpty) return [];
    final all = <TransactionRecord>[];
    for (final ledgerUuid in ledgerUuids) {
      all.addAll(
        await getTransactionsForLedger(
          ledgerUuid,
          includeDeleted: includeDeleted,
        ),
      );
    }
    all.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return all;
  }

  Future<void> saveTransaction(TransactionRecord transaction) async {
    await _ensureReady();
    final target = await _transactionTargetScope(transaction);
    final transactions = await _readTransactionsForScope(target);
    _upsertByUuid<TransactionRecord>(
      transactions,
      transaction,
      uuidOf: (value) => value.uuid,
      assignId: (value) =>
          value.id = _nextId(transactions.map((item) => item.id)),
    );
    await _writeTransactionsForScope(target, transactions);
  }

  Future<void> deleteTransaction(String uuid) async {
    await _ensureReady();
    final found = await _findTransactionWithScope(uuid);
    if (found == null) return;
    final transactions = await _readTransactionsForScope(found.key);
    final transaction = transactions
        .where((item) => item.uuid == uuid)
        .firstOrNull;
    if (transaction == null) return;
    transaction.isDeleted = true;
    await _writeTransactionsForScope(found.key, transactions);
  }

  List<LocalDataScope> _visibleScopes() {
    if (scope.isGuest) return [const LocalDataScope.guest()];
    return [const LocalDataScope.guest(), scope];
  }

  Future<List<Ledger>> _visibleLedgers() async {
    final ledgers = <Ledger>[];
    for (final target in _visibleScopes()) {
      ledgers.addAll(await _readLedgersForScope(target));
    }
    final byScopeAndUuid = <String, Ledger>{};
    for (final ledger in ledgers) {
      byScopeAndUuid['${ledger.localAccountUuid ?? 'guest'}:${ledger.uuid}'] =
          ledger;
    }
    return byScopeAndUuid.values.toList();
  }

  Future<List<Person>> _visiblePeople() async {
    final people = <Person>[];
    for (final target in _visibleScopes()) {
      people.addAll(await _readPeopleForScope(target));
    }
    final byUuid = <String, Person>{};
    for (final person in people) {
      byUuid[person.uuid] = person;
    }
    return byUuid.values.toList();
  }

  Future<List<TransactionRecord>> _visibleTransactions() async {
    final transactions = <TransactionRecord>[];
    for (final target in _visibleScopes()) {
      transactions.addAll(await _readTransactionsForScope(target));
    }
    final byScopeAndUuid = <String, TransactionRecord>{};
    for (final transaction in transactions) {
      byScopeAndUuid['${transaction.localAccountUuid ?? 'guest'}:${transaction.uuid}'] =
          transaction;
    }
    return byScopeAndUuid.values.toList();
  }

  Future<LocalDataScope> _ledgerTargetScope(Ledger ledger) async {
    final owner = ledger.localAccountUuid;
    if (owner != null && owner.isNotEmpty) return LocalDataScope.account(owner);
    if (scope.isAccount) {
      final existing = await _readLedgersForScope(scope);
      if (existing.any((item) => item.uuid == ledger.uuid)) return scope;
    }
    return const LocalDataScope.guest();
  }

  Future<LocalDataScope> _personTargetScope(Person person) async {
    final owner = person.localAccountUuid;
    if (owner != null && owner.isNotEmpty) return LocalDataScope.account(owner);
    final ledgerUuid = person.pendingLedgerUuid;
    if (ledgerUuid != null) {
      final ledger = await _findLedgerWithScope(ledgerUuid);
      if (ledger != null) return ledger.key;
    }
    if (scope.isAccount) {
      final accountPeople = await _readPeopleForScope(scope);
      if (accountPeople.any((item) => item.uuid == person.uuid)) return scope;
    }
    return const LocalDataScope.guest();
  }

  Future<LocalDataScope> _transactionTargetScope(
    TransactionRecord transaction,
  ) async {
    final owner = transaction.localAccountUuid;
    if (owner != null && owner.isNotEmpty) return LocalDataScope.account(owner);
    final ledger = await _findLedgerWithScope(transaction.ledgerUuid);
    if (ledger != null) return ledger.key;
    return const LocalDataScope.guest();
  }

  Future<_Scoped<Ledger>?> _findLedgerWithScope(String uuid) async {
    for (final target in _visibleScopes().reversed) {
      final ledgers = await _readLedgersForScope(target);
      final ledger = ledgers
          .where((item) => item.uuid == uuid || item.syncedRemoteUuid == uuid)
          .firstOrNull;
      if (ledger != null) return _Scoped(target, ledger);
    }
    return null;
  }

  Future<_Scoped<Person>?> _findPersonWithScope(String uuid) async {
    for (final target in _visibleScopes().reversed) {
      final people = await _readPeopleForScope(target);
      final person = people.where((item) => item.uuid == uuid).firstOrNull;
      if (person != null) return _Scoped(target, person);
    }
    return null;
  }

  Future<_Scoped<TransactionRecord>?> _findTransactionWithScope(
    String uuid,
  ) async {
    for (final target in _visibleScopes().reversed) {
      final transactions = await _readTransactionsForScope(target);
      final transaction = transactions
          .where((item) => item.uuid == uuid)
          .firstOrNull;
      if (transaction != null) return _Scoped(target, transaction);
    }
    return null;
  }

  Future<List<Person>> _readPeople() => _readPeopleForScope(scope);

  Future<List<Person>> _readPeopleForScope(LocalDataScope target) async {
    return (await _readJsonList(
      _peopleKeyFor(target),
    )).map(_personFromJson).toList();
  }

  Future<List<Ledger>> _readLedgersForScope(LocalDataScope target) async {
    return (await _readJsonList(
      _ledgersKeyFor(target),
    )).map(_ledgerFromJson).toList();
  }

  Future<List<TransactionRecord>> _readTransactionsForScope(
    LocalDataScope target,
  ) async {
    return (await _readJsonList(
      _transactionsKeyFor(target),
    )).map(_transactionFromJson).toList();
  }

  Future<void> _writePeople(List<Person> people) =>
      _writePeopleForScope(scope, people);

  Future<void> _writePeopleForScope(
    LocalDataScope target,
    List<Person> people,
  ) {
    return _writeJsonList(
      _peopleKeyFor(target),
      people.map(_personToJson).toList(),
    );
  }

  Future<void> _writeLedgersForScope(
    LocalDataScope target,
    List<Ledger> ledgers,
  ) {
    return _writeJsonList(
      _ledgersKeyFor(target),
      ledgers.map(_ledgerToJson).toList(),
    );
  }

  Future<void> _writeTransactionsForScope(
    LocalDataScope target,
    List<TransactionRecord> transactions,
  ) {
    return _writeJsonList(
      _transactionsKeyFor(target),
      transactions.map(_transactionToJson).toList(),
    );
  }

  String _peopleKeyFor(LocalDataScope target) =>
      'local_store.${target.storageKey}.people.v2';

  String _ledgersKeyFor(LocalDataScope target) =>
      'local_store.${target.storageKey}.ledgers.v2';

  String _transactionsKeyFor(LocalDataScope target) =>
      'local_store.${target.storageKey}.transactions.v2';

  Future<List<Map<String, dynamic>>> _readJsonList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List<dynamic>) return [];
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map((value) => value.cast<String, dynamic>())
        .toList();
  }

  Future<void> _writeJsonList(
    String key,
    List<Map<String, dynamic>> values,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(values));
  }

  void _upsertByUuid<T>(
    List<T> items,
    T item, {
    required String Function(T value) uuidOf,
    required void Function(T value) assignId,
  }) {
    final index = items.indexWhere((value) => uuidOf(value) == uuidOf(item));
    if (index == -1) {
      assignId(item);
      items.add(item);
      return;
    }
    items[index] = item;
  }

  int _nextId(Iterable<int> ids) {
    return ids.fold<int>(0, (max, id) => id > max ? id : max) + 1;
  }

  static Person _personFromJson(Map<String, dynamic> json) {
    return Person()
      ..id = (json['id'] as num?)?.toInt() ?? 0
      ..version = (json['version'] as num?)?.toInt() ?? 1
      ..uuid = json['uuid']?.toString() ?? ''
      ..name = json['name']?.toString() ?? ''
      ..avatar = json['avatar']?.toString() ?? '🧑'
      ..linkedUserUuid = json['linkedUserUuid']?.toString()
      ..syncedRemoteUuid = json['syncedRemoteUuid']?.toString()
      ..localAccountUuid = json['localAccountUuid']?.toString()
      ..isDeleted = json['isDeleted'] == true
      ..pendingSync = json['pendingSync'] == true
      ..syncError = json['syncError']?.toString()
      ..pendingLedgerUuid = json['pendingLedgerUuid']?.toString();
  }

  static Map<String, dynamic> _personToJson(Person person) {
    return {
      'id': person.id,
      'version': person.version,
      'uuid': person.uuid,
      'name': person.name,
      'avatar': person.avatar,
      'linkedUserUuid': person.linkedUserUuid,
      'syncedRemoteUuid': person.syncedRemoteUuid,
      'localAccountUuid': person.localAccountUuid,
      'isDeleted': person.isDeleted,
      'pendingSync': person.pendingSync,
      'syncError': person.syncError,
      'pendingLedgerUuid': person.pendingLedgerUuid,
    };
  }

  static Ledger _ledgerFromJson(Map<String, dynamic> json) {
    return Ledger()
      ..id = (json['id'] as num?)?.toInt() ?? 0
      ..version = (json['version'] as num?)?.toInt() ?? 1
      ..uuid = json['uuid']?.toString() ?? ''
      ..name = json['name']?.toString() ?? ''
      ..baseCurrencyCode = json['baseCurrencyCode']?.toString() ?? 'CNY'
      ..exchangeRateToCNY =
          (json['exchangeRateToCNY'] as num?)?.toDouble() ?? 1.0
      ..personUuids = (json['personUuids'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList()
      ..sortOrder = (json['sortOrder'] as num?)?.toInt() ?? 0
      ..isDeleted = json['isDeleted'] == true
      ..role = json['role']?.toString()
      ..memberCount = (json['memberCount'] as num?)?.toInt() ?? 1
      ..members = (json['members'] as List<dynamic>? ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map((value) => _ledgerMemberFromJson(value.cast<String, dynamic>()))
          .toList()
      ..syncedRemoteUuid = json['syncedRemoteUuid']?.toString()
      ..localAccountUuid = json['localAccountUuid']?.toString()
      ..cacheOwnerUserUuid = json['cacheOwnerUserUuid']?.toString()
      ..cloudPolicy = _ledgerCloudPolicyFromJson(json['cloudPolicy'])
      ..pendingSync = json['pendingSync'] == true
      ..claimPending = json['claimPending'] == true
      ..syncError = json['syncError']?.toString();
  }

  static Map<String, dynamic> _ledgerToJson(Ledger ledger) {
    return {
      'id': ledger.id,
      'version': ledger.version,
      'uuid': ledger.uuid,
      'name': ledger.name,
      'baseCurrencyCode': ledger.baseCurrencyCode,
      'exchangeRateToCNY': ledger.exchangeRateToCNY,
      'personUuids': ledger.personUuids,
      'sortOrder': ledger.sortOrder,
      'isDeleted': ledger.isDeleted,
      'role': ledger.role,
      'memberCount': ledger.memberCount,
      'members': ledger.members.map(_ledgerMemberToJson).toList(),
      'syncedRemoteUuid': ledger.syncedRemoteUuid,
      'localAccountUuid': ledger.localAccountUuid,
      'cacheOwnerUserUuid': ledger.cacheOwnerUserUuid,
      'cloudPolicy': ledger.cloudPolicy.name,
      'pendingSync': ledger.pendingSync,
      'claimPending': ledger.claimPending,
      'syncError': ledger.syncError,
    };
  }

  static LedgerCloudPolicy _ledgerCloudPolicyFromJson(Object? value) {
    return LedgerCloudPolicy.values.where((policy) {
          return policy.name == value?.toString();
        }).firstOrNull ??
        LedgerCloudPolicy.localOnly;
  }

  static LedgerMemberSummary _ledgerMemberFromJson(Map<String, dynamic> json) {
    return LedgerMemberSummary(
      uuid: json['uuid']?.toString() ?? '',
      userUuid: json['userUuid']?.toString(),
      nickname: json['nickname']?.toString(),
      avatar: json['avatar']?.toString(),
      role: json['role']?.toString(),
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  static Map<String, dynamic> _ledgerMemberToJson(LedgerMemberSummary member) {
    return {
      'uuid': member.uuid,
      'userUuid': member.userUuid,
      'nickname': member.nickname,
      'avatar': member.avatar,
      'role': member.role,
      'version': member.version,
    };
  }

  static TransactionRecord _transactionFromJson(Map<String, dynamic> json) {
    return TransactionRecord()
      ..id = (json['id'] as num?)?.toInt() ?? 0
      ..uuid = json['uuid']?.toString() ?? ''
      ..ledgerUuid = json['ledgerUuid']?.toString() ?? ''
      ..type = (json['type'] as num?)?.toInt() ?? 0
      ..payerPersonUuid = json['payerPersonUuid']?.toString()
      ..clientOperationId = json['clientOperationId']?.toString()
      ..version = (json['version'] as num?)?.toInt() ?? 1
      ..amount = (json['amount'] as num?)?.toDouble() ?? 0
      ..currencyCode = json['currencyCode']?.toString() ?? 'CNY'
      ..category = json['category']?.toString() ?? ''
      ..personUuids = (json['personUuids'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList()
      ..note = json['note']?.toString() ?? ''
      ..createdByUserUuid = json['createdByUserUuid']?.toString()
      ..createdByNickname = json['createdByNickname']?.toString()
      ..createdByAvatar = json['createdByAvatar']?.toString()
      ..localAccountUuid = json['localAccountUuid']?.toString()
      ..createdAt =
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now()
      ..pendingSync = json['pendingSync'] == true
      ..syncError = json['syncError']?.toString()
      ..isDeleted = json['isDeleted'] == true;
  }

  static Map<String, dynamic> _transactionToJson(
    TransactionRecord transaction,
  ) {
    return {
      'id': transaction.id,
      'uuid': transaction.uuid,
      'ledgerUuid': transaction.ledgerUuid,
      'type': transaction.type,
      'payerPersonUuid': transaction.payerPersonUuid,
      'clientOperationId': transaction.clientOperationId,
      'version': transaction.version,
      'amount': transaction.amount,
      'currencyCode': transaction.currencyCode,
      'category': transaction.category,
      'personUuids': transaction.personUuids,
      'note': transaction.note,
      'createdByUserUuid': transaction.createdByUserUuid,
      'createdByNickname': transaction.createdByNickname,
      'createdByAvatar': transaction.createdByAvatar,
      'localAccountUuid': transaction.localAccountUuid,
      'createdAt': transaction.createdAt.toIso8601String(),
      'pendingSync': transaction.pendingSync,
      'syncError': transaction.syncError,
      'isDeleted': transaction.isDeleted,
    };
  }
}

class _Scoped<T> {
  const _Scoped(this.key, this.value);

  final LocalDataScope key;
  final T value;
}

final dbService = DatabaseService();
