import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ledger.dart';
import '../models/person.dart';
import '../models/transaction_record.dart';

class DatabaseService {
  static const _peopleKey = 'local_store.people.v1';
  static const _ledgersKey = 'local_store.ledgers.v1';
  static const _transactionsKey = 'local_store.transactions.v1';

  Future<void> init() async {
    final people = await _readPeople();
    if (people.isNotEmpty) {
      return;
    }

    await _writePeople([
      Person()
        ..id = 1
        ..uuid = 'self'
        ..name = '自己'
        ..avatar = '😎',
    ]);
  }

  // Person operations
  Future<List<Person>> getAllPeople({bool includeDeleted = false}) async {
    final people = await _readPeople();
    if (includeDeleted) {
      return people;
    }
    return people.where((person) => !person.isDeleted).toList();
  }

  Future<void> savePerson(Person person) async {
    final people = await _readPeople();
    _upsertByUuid<Person>(
      people,
      person,
      uuidOf: (value) => value.uuid,
      assignId: (value) => value.id = _nextId(people.map((item) => item.id)),
    );
    await _writePeople(people);
  }

  Future<void> deletePerson(String uuid) async {
    final people = await _readPeople();
    final person = people.where((item) => item.uuid == uuid).firstOrNull;
    if (person == null) {
      return;
    }
    person.isDeleted = true;
    await _writePeople(people);
  }

  Future<void> replacePersonUuidReferences({
    required String oldUuid,
    required String newUuid,
  }) async {
    if (oldUuid == newUuid) {
      return;
    }

    final people = await _readPeople();
    final oldPersonIndex = people.indexWhere(
      (person) => person.uuid == oldUuid,
    );
    final newPersonIndex = people.indexWhere(
      (person) => person.uuid == newUuid,
    );
    if (oldPersonIndex != -1 && newPersonIndex != -1) {
      people.removeAt(oldPersonIndex);
      await _writePeople(people);
    } else if (oldPersonIndex != -1) {
      people[oldPersonIndex].uuid = newUuid;
      await _writePeople(people);
    }

    final ledgers = await _readLedgers();
    var ledgersChanged = false;
    for (final ledger in ledgers) {
      if (!ledger.personUuids.contains(oldUuid)) {
        continue;
      }
      ledger.personUuids = ledger.personUuids
          .map((uuid) => uuid == oldUuid ? newUuid : uuid)
          .toSet()
          .toList();
      ledgersChanged = true;
    }
    if (ledgersChanged) {
      await _writeLedgers(ledgers);
    }

    final transactions = await _readTransactions();
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
      await _writeTransactions(transactions);
    }
  }

  // Ledger operations
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    final ledgers = await _readLedgers();
    final visible = includeDeleted
        ? ledgers
        : ledgers.where((ledger) => !ledger.isDeleted).toList();
    visible.sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    return visible;
  }

  Future<void> saveLedger(Ledger ledger) async {
    final ledgers = await _readLedgers();
    _upsertByUuid<Ledger>(
      ledgers,
      ledger,
      uuidOf: (value) => value.uuid,
      assignId: (value) => value.id = _nextId(ledgers.map((item) => item.id)),
    );
    await _writeLedgers(ledgers);
  }

  Future<void> deleteLedger(String uuid) async {
    final ledgers = await _readLedgers();
    final ledger = ledgers.where((item) => item.uuid == uuid).firstOrNull;
    if (ledger != null) {
      ledger.isDeleted = true;
      await _writeLedgers(ledgers);
    }

    final transactions = await _readTransactions();
    var changed = false;
    for (final transaction in transactions) {
      if (transaction.ledgerUuid == uuid && !transaction.isDeleted) {
        transaction.isDeleted = true;
        changed = true;
      }
    }
    if (changed) {
      await _writeTransactions(transactions);
    }
  }

  Future<void> hideLedger(String uuid) async {
    final ledgers = await _readLedgers();
    final ledger = ledgers.where((item) {
      return item.uuid == uuid || item.syncedRemoteUuid == uuid;
    }).firstOrNull;
    if (ledger == null) {
      return;
    }
    ledger.isDeleted = true;
    await _writeLedgers(ledgers);
  }

  Future<void> restoreLedgerAccess(String uuid) async {
    final ledgers = await _readLedgers();
    final ledger = ledgers.where((item) {
      return item.uuid == uuid || item.syncedRemoteUuid == uuid;
    }).firstOrNull;
    if (ledger == null) {
      return;
    }
    ledger
      ..isDeleted = false
      ..pendingSync = false
      ..syncError = null;
    await _writeLedgers(ledgers);
  }

  // Transaction operations
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) async {
    final transactions = await _readTransactions();
    final visible = transactions.where((transaction) {
      if (transaction.ledgerUuid != ledgerUuid) {
        return false;
      }
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

    final ledgerUuidSet = ledgerUuids.toSet();
    final transactions = await _readTransactions();
    final visible = transactions.where((transaction) {
      if (!ledgerUuidSet.contains(transaction.ledgerUuid)) {
        return false;
      }
      return includeDeleted || !transaction.isDeleted;
    }).toList();
    visible.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return visible;
  }

  Future<void> saveTransaction(TransactionRecord transaction) async {
    final transactions = await _readTransactions();
    _upsertByUuid<TransactionRecord>(
      transactions,
      transaction,
      uuidOf: (value) => value.uuid,
      assignId: (value) =>
          value.id = _nextId(transactions.map((item) => item.id)),
    );
    await _writeTransactions(transactions);
  }

  Future<void> deleteTransaction(String uuid) async {
    final transactions = await _readTransactions();
    final transaction = transactions
        .where((item) => item.uuid == uuid)
        .firstOrNull;
    if (transaction == null) {
      return;
    }
    transaction.isDeleted = true;
    await _writeTransactions(transactions);
  }

  Future<List<Person>> _readPeople() async {
    final values = await _readJsonList(_peopleKey);
    return values.map(_personFromJson).toList();
  }

  Future<void> _writePeople(List<Person> people) {
    return _writeJsonList(_peopleKey, people.map(_personToJson).toList());
  }

  Future<List<Ledger>> _readLedgers() async {
    final values = await _readJsonList(_ledgersKey);
    return values.map(_ledgerFromJson).toList();
  }

  Future<void> _writeLedgers(List<Ledger> ledgers) {
    return _writeJsonList(_ledgersKey, ledgers.map(_ledgerToJson).toList());
  }

  Future<List<TransactionRecord>> _readTransactions() async {
    final values = await _readJsonList(_transactionsKey);
    return values.map(_transactionFromJson).toList();
  }

  Future<void> _writeTransactions(List<TransactionRecord> transactions) {
    return _writeJsonList(
      _transactionsKey,
      transactions.map(_transactionToJson).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _readJsonList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return [];
    }
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
      ..uuid = json['uuid']?.toString() ?? ''
      ..name = json['name']?.toString() ?? ''
      ..avatar = json['avatar']?.toString() ?? '🧑'
      ..linkedUserUuid = json['linkedUserUuid']?.toString()
      ..syncedRemoteUuid = json['syncedRemoteUuid']?.toString()
      ..isDeleted = json['isDeleted'] == true
      ..pendingSync = json['pendingSync'] == true
      ..syncError = json['syncError']?.toString()
      ..pendingLedgerUuid = json['pendingLedgerUuid']?.toString();
  }

  static Map<String, dynamic> _personToJson(Person person) {
    return {
      'id': person.id,
      'uuid': person.uuid,
      'name': person.name,
      'avatar': person.avatar,
      'linkedUserUuid': person.linkedUserUuid,
      'syncedRemoteUuid': person.syncedRemoteUuid,
      'isDeleted': person.isDeleted,
      'pendingSync': person.pendingSync,
      'syncError': person.syncError,
      'pendingLedgerUuid': person.pendingLedgerUuid,
    };
  }

  static Ledger _ledgerFromJson(Map<String, dynamic> json) {
    return Ledger()
      ..id = (json['id'] as num?)?.toInt() ?? 0
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
      ..cacheOwnerUserUuid = json['cacheOwnerUserUuid']?.toString()
      ..cloudPolicy = _ledgerCloudPolicyFromJson(json['cloudPolicy'])
      ..pendingSync = json['pendingSync'] == true
      ..syncError = json['syncError']?.toString();
  }

  static Map<String, dynamic> _ledgerToJson(Ledger ledger) {
    return {
      'id': ledger.id,
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
      'cacheOwnerUserUuid': ledger.cacheOwnerUserUuid,
      'cloudPolicy': ledger.cloudPolicy.name,
      'pendingSync': ledger.pendingSync,
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
    );
  }

  static Map<String, dynamic> _ledgerMemberToJson(LedgerMemberSummary member) {
    return {
      'uuid': member.uuid,
      'userUuid': member.userUuid,
      'nickname': member.nickname,
      'avatar': member.avatar,
      'role': member.role,
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
      ..version = (json['version'] as num?)?.toInt()
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
      'createdAt': transaction.createdAt.toIso8601String(),
      'pendingSync': transaction.pendingSync,
      'syncError': transaction.syncError,
      'isDeleted': transaction.isDeleted,
    };
  }
}

// Global instance for simple access (will be replaced by Riverpod later as per rules)
final dbService = DatabaseService();
