import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/person.dart';
import '../models/transaction_record.dart';
import '../network/api_client.dart';

class LocalLedgerImportCandidate {
  const LocalLedgerImportCandidate({
    required this.ledger,
    required this.transactionCount,
    required this.imported,
    this.remoteLedgerUuid,
  });

  final Ledger ledger;
  final int transactionCount;
  final bool imported;
  final String? remoteLedgerUuid;
}

class CloudImportProgress {
  const CloudImportProgress({
    required this.message,
    required this.done,
    required this.total,
  });

  final String message;
  final int done;
  final int total;
}

class CloudImportService {
  const CloudImportService({
    required DatabaseService database,
    required ApiClient apiClient,
  }) : _database = database,
       _apiClient = apiClient;

  final DatabaseService _database;
  final ApiClient _apiClient;

  Future<List<LocalLedgerImportCandidate>> scanLocalLedgers() async {
    final prefs = await SharedPreferences.getInstance();
    final ledgers = await _database.getAllLedgers();
    final candidates = <LocalLedgerImportCandidate>[];

    for (final ledger in ledgers) {
      final remoteUuid = prefs.getString(_importedLedgerKey(ledger.uuid));
      final transactions = await _database.getTransactionsForLedger(
        ledger.uuid,
      );
      candidates.add(
        LocalLedgerImportCandidate(
          ledger: ledger,
          transactionCount: transactions.length,
          imported: remoteUuid != null,
          remoteLedgerUuid: remoteUuid,
        ),
      );
    }

    return candidates;
  }

  Future<void> importLedgers(
    List<String> ledgerUuids, {
    void Function(CloudImportProgress progress)? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ledgers = await _database.getAllLedgers();
    final selectedLedgers = ledgers
        .where((ledger) => ledgerUuids.contains(ledger.uuid))
        .toList();
    final people = await _database.getAllPeople(includeDeleted: true);
    final peopleByUuid = {for (final person in people) person.uuid: person};

    for (var index = 0; index < selectedLedgers.length; index++) {
      final ledger = selectedLedgers[index];
      final step = index + 1;
      onProgress?.call(
        CloudImportProgress(
          message: '正在导入 ${ledger.name}',
          done: index,
          total: selectedLedgers.length,
        ),
      );

      final existingRemoteUuid = prefs.getString(
        _importedLedgerKey(ledger.uuid),
      );
      if (existingRemoteUuid != null) {
        onProgress?.call(
          CloudImportProgress(
            message: '${ledger.name} 已导入，已跳过',
            done: step,
            total: selectedLedgers.length,
          ),
        );
        continue;
      }

      final remoteLedger = await _createLedger(ledger);
      final personUuidMap = await _uploadPeople(
        localLedger: ledger,
        remoteLedgerUuid: remoteLedger.uuid,
        peopleByUuid: peopleByUuid,
      );
      await _uploadTransactions(
        localLedger: ledger,
        remoteLedgerUuid: remoteLedger.uuid,
        personUuidMap: personUuidMap,
      );

      await prefs.setString(_importedLedgerKey(ledger.uuid), remoteLedger.uuid);
      onProgress?.call(
        CloudImportProgress(
          message: '${ledger.name} 导入完成',
          done: step,
          total: selectedLedgers.length,
        ),
      );
    }
  }

  Future<Ledger> _createLedger(Ledger ledger) {
    return _apiClient.post<Ledger>(
      '/api/ledgers',
      data: {
        'name': ledger.name,
        'baseCurrencyCode': ledger.baseCurrencyCode,
        'exchangeRateToCny': ledger.exchangeRateToCNY,
      },
      idempotencyKey: 'import-ledger-${ledger.uuid}',
      fromJson: _ledgerFromJson,
    );
  }

  Future<Map<String, String>> _uploadPeople({
    required Ledger localLedger,
    required String remoteLedgerUuid,
    required Map<String, Person> peopleByUuid,
  }) async {
    final transactions = await _database.getTransactionsForLedger(
      localLedger.uuid,
    );
    final personUuids = <String>{
      ...localLedger.personUuids,
      for (final transaction in transactions) ...transaction.personUuids,
    };
    final personUuidMap = <String, String>{};

    for (final personUuid in personUuids) {
      final person = peopleByUuid[personUuid] ?? _fallbackPerson(personUuid);
      final remotePerson = await _apiClient.post<Person>(
        '/api/ledgers/$remoteLedgerUuid/people',
        data: {'name': person.name, 'avatar': person.avatar},
        idempotencyKey: 'import-person-${localLedger.uuid}-$personUuid',
        fromJson: _personFromJson,
      );
      personUuidMap[personUuid] = remotePerson.uuid;
    }

    return personUuidMap;
  }

  Future<void> _uploadTransactions({
    required Ledger localLedger,
    required String remoteLedgerUuid,
    required Map<String, String> personUuidMap,
  }) async {
    final transactions = await _database.getTransactionsForLedger(
      localLedger.uuid,
    );
    for (final transaction in transactions) {
      final remotePersonUuids = transaction.personUuids
          .map((uuid) => personUuidMap[uuid])
          .whereType<String>()
          .toList();
      if (remotePersonUuids.isEmpty) {
        continue;
      }

      await _apiClient.post<TransactionRecord>(
        '/api/ledgers/$remoteLedgerUuid/transactions',
        data: {
          'type': transaction.type,
          'amount': transaction.amount,
          'currencyCode': transaction.currencyCode,
          'category': transaction.category,
          'note': transaction.note,
          'happenedAt': transaction.createdAt.toIso8601String(),
          'clientOperationId': 'import-${transaction.uuid}',
          'personUuids': remotePersonUuids,
        },
        idempotencyKey:
            'import-transaction-${localLedger.uuid}-${transaction.uuid}',
        fromJson: _transactionFromJson,
      );
    }
  }

  String _importedLedgerKey(String ledgerUuid) {
    return 'cloud_import.ledger.$ledgerUuid';
  }

  static Ledger _ledgerFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Ledger()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..baseCurrencyCode = map['baseCurrencyCode'].toString()
      ..exchangeRateToCNY =
          (map['exchangeRateToCny'] as num?)?.toDouble() ?? 1.0
      ..role = map['role']?.toString();
  }

  static Person _personFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Person()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..avatar = map['avatar']?.toString() ?? '';
  }

  static TransactionRecord _transactionFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return TransactionRecord()
      ..uuid = map['uuid'].toString()
      ..ledgerUuid = map['ledgerUuid'].toString()
      ..type = (map['type'] as num?)?.toInt() ?? 0
      ..amount = (map['amount'] as num?)?.toDouble() ?? 0
      ..currencyCode = map['currencyCode'].toString()
      ..category = map['category'].toString()
      ..note = map['note']?.toString() ?? ''
      ..personUuids = (map['personUuids'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList()
      ..createdAt =
          DateTime.tryParse(map['happenedAt']?.toString() ?? '') ??
          DateTime.now();
  }

  static Person _fallbackPerson(String uuid) {
    return Person()
      ..uuid = uuid
      ..name = '未知人员'
      ..avatar = '?';
  }
}
