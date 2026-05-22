import '../database/database_service.dart';
import '../models/transaction_record.dart';
import '../network/api_client.dart';

abstract class TransactionRepository {
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  });

  Future<List<TransactionRecord>> getTransactionsForLedgers(
    List<String> ledgerUuids, {
    bool includeDeleted = false,
  });

  Future<void> saveTransaction(TransactionRecord transaction);

  Future<void> deleteTransaction(String ledgerUuid, String uuid);
}

class LocalTransactionRepository implements TransactionRepository {
  const LocalTransactionRepository(this._db);

  final DatabaseService _db;

  @override
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) {
    return _db.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<List<TransactionRecord>> getTransactionsForLedgers(
    List<String> ledgerUuids, {
    bool includeDeleted = false,
  }) {
    return _db.getTransactionsForLedgers(
      ledgerUuids,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<void> saveTransaction(TransactionRecord transaction) {
    return _db.saveTransaction(transaction);
  }

  @override
  Future<void> deleteTransaction(String ledgerUuid, String uuid) {
    return _db.deleteTransaction(uuid);
  }
}

class RemoteTransactionRepository implements TransactionRepository {
  const RemoteTransactionRepository(this._apiClient);

  static const int _pageSize = 100;

  final ApiClient _apiClient;

  @override
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) async {
    final all = <TransactionRecord>[];
    var page = 1;
    var total = 0;

    do {
      final pageData = await _getTransactionPage(ledgerUuid, page);
      total = pageData.total;
      all.addAll(pageData.records);
      if (pageData.records.isEmpty) {
        break;
      }
      page += 1;
    } while (all.length < total);

    return all;
  }

  @override
  Future<List<TransactionRecord>> getTransactionsForLedgers(
    List<String> ledgerUuids, {
    bool includeDeleted = false,
  }) async {
    final all = <TransactionRecord>[];
    for (final ledgerUuid in ledgerUuids) {
      all.addAll(
        await getTransactionsForLedger(
          ledgerUuid,
          includeDeleted: includeDeleted,
        ),
      );
    }
    return all;
  }

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {
    final data = {
      'type': transaction.type,
      'amount': transaction.amount,
      'currencyCode': transaction.currencyCode,
      'category': transaction.category,
      'note': transaction.note,
      'happenedAt': transaction.createdAt.toIso8601String(),
      'clientOperationId': transaction.uuid,
      'personUuids': transaction.personUuids,
    };

    final version = _versionByUuid[transaction.uuid];
    if (version == null) {
      await _apiClient.post<TransactionRecord>(
        '/api/ledgers/${transaction.ledgerUuid}/transactions',
        data: data,
        idempotencyKey: transaction.uuid,
        fromJson: _transactionFromJson,
      );
      return;
    }

    await _apiClient.put<TransactionRecord>(
      '/api/ledgers/${transaction.ledgerUuid}/transactions/${transaction.uuid}',
      data: {...data, 'version': version},
      idempotencyKey: 'update-transaction-${transaction.uuid}-$version',
      fromJson: _transactionFromJson,
    );
  }

  @override
  Future<void> deleteTransaction(String ledgerUuid, String uuid) async {
    final transaction = await _apiClient.get<TransactionRecord>(
      '/api/ledgers/$ledgerUuid/transactions/$uuid',
      fromJson: _transactionFromJson,
    );
    await _apiClient.deleteVoid(
      '/api/ledgers/$ledgerUuid/transactions/$uuid',
      data: {'version': _versionByUuid[transaction.uuid] ?? 1},
      idempotencyKey: 'delete-transaction-$uuid',
    );
  }

  static final Map<String, int> _versionByUuid = {};

  Future<_TransactionPage> _getTransactionPage(String ledgerUuid, int page) {
    return _apiClient.get<_TransactionPage>(
      '/api/ledgers/$ledgerUuid/transactions',
      queryParameters: {'page': page, 'pageSize': _pageSize},
      fromJson: (json) {
        final map = json! as Map<String, dynamic>;
        final records = map['records'] as List<dynamic>? ?? [];
        return _TransactionPage(
          total: (map['total'] as num?)?.toInt() ?? records.length,
          records: records.map(_transactionFromJson).toList(),
        );
      },
    );
  }

  static TransactionRecord _transactionFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    final uuid = map['uuid'].toString();
    _versionByUuid[uuid] = (map['version'] as num?)?.toInt() ?? 1;
    return TransactionRecord()
      ..uuid = uuid
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
}

class _TransactionPage {
  const _TransactionPage({required this.total, required this.records});

  final int total;
  final List<TransactionRecord> records;
}
