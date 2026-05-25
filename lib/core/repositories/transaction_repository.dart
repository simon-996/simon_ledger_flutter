import 'dart:async';

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

class TransactionSyncResult {
  const TransactionSyncResult({required this.synced, this.error});

  final int synced;
  final Object? error;
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
  const RemoteTransactionRepository({
    required ApiClient apiClient,
    required DatabaseService database,
  }) : _apiClient = apiClient,
       _db = database;

  static const int _pageSize = 100;

  final ApiClient _apiClient;
  final DatabaseService _db;

  @override
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) async {
    final localTransactions = await _db.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );

    try {
      await syncPendingTransactions(ledgerUuid);
      final remoteTransactions = await _fetchRemoteTransactions(ledgerUuid);
      final latestLocalTransactions = await _db.getTransactionsForLedger(
        ledgerUuid,
        includeDeleted: includeDeleted,
      );
      final latestPending = latestLocalTransactions
          .where((transaction) => transaction.pendingSync)
          .toList();

      return _mergeTransactions(remoteTransactions, latestPending);
    } catch (_) {
      return localTransactions;
    }
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
    final local = _localPendingTransaction(transaction);
    await _db.saveTransaction(local);
    transaction
      ..clientOperationId = local.clientOperationId
      ..pendingSync = local.pendingSync
      ..syncError = local.syncError;
    unawaited(syncPendingTransactions(transaction.ledgerUuid));
  }

  Future<TransactionSyncResult> syncPendingTransactions(
    String ledgerUuid,
  ) async {
    final transactions = await _db.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: true,
    );
    final pending = transactions
        .where(
          (transaction) => transaction.pendingSync && !transaction.isDeleted,
        )
        .toList();
    var synced = 0;
    Object? firstError;

    for (final transaction in pending) {
      try {
        await _uploadPendingTransaction(transaction);
        synced += 1;
      } catch (error) {
        firstError ??= error;
        transaction
          ..pendingSync = true
          ..syncError = error.toString();
        await _db.saveTransaction(transaction);
      }
    }

    return TransactionSyncResult(synced: synced, error: firstError);
  }

  Future<void> _uploadPendingTransaction(TransactionRecord transaction) async {
    final data = {
      'type': transaction.type,
      'payerPersonUuid': transaction.payerPersonUuid,
      'amount': transaction.amount,
      'currencyCode': transaction.currencyCode,
      'category': transaction.category,
      'note': transaction.note,
      'happenedAt': transaction.createdAt.toIso8601String(),
      'clientOperationId': transaction.clientOperationId ?? transaction.uuid,
      'personUuids': transaction.personUuids,
    };

    final remoteUuid =
        _remoteUuidByOperationId[transaction.clientOperationId] ??
        (_looksLikeRemoteUuid(transaction.uuid) ? transaction.uuid : null);
    final version = transaction.version ?? _versionByUuid[transaction.uuid];
    if (remoteUuid == null || version == null) {
      final saved = await _apiClient.post<TransactionRecord>(
        '/api/ledgers/${transaction.ledgerUuid}/transactions',
        data: data,
        idempotencyKey: transaction.clientOperationId ?? transaction.uuid,
        fromJson: _transactionFromJson,
      );
      await _saveSyncedTransaction(transaction, saved);
      return;
    }

    final saved = await _apiClient.put<TransactionRecord>(
      '/api/ledgers/${transaction.ledgerUuid}/transactions/$remoteUuid',
      data: {...data, 'version': version},
      idempotencyKey: 'update-transaction-$remoteUuid-$version',
      fromJson: _transactionFromJson,
    );
    await _saveSyncedTransaction(transaction, saved);
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
  static final Map<String, String> _remoteUuidByOperationId = {};

  static bool _looksLikeRemoteUuid(String uuid) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid);
  }

  Future<List<TransactionRecord>> _fetchRemoteTransactions(
    String ledgerUuid,
  ) async {
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

    for (final transaction in all) {
      await _db.saveTransaction(transaction);
    }
    return all;
  }

  TransactionRecord _localPendingTransaction(TransactionRecord transaction) {
    final clientOperationId = transaction.clientOperationId ?? transaction.uuid;
    return transaction
      ..clientOperationId = clientOperationId
      ..pendingSync = true
      ..syncError = null;
  }

  Future<void> _saveSyncedTransaction(
    TransactionRecord local,
    TransactionRecord remote,
  ) async {
    local.isDeleted = true;
    await _db.saveTransaction(local);

    await _db.saveTransaction(
      remote
        ..clientOperationId = local.clientOperationId
        ..pendingSync = false
        ..syncError = null,
    );
  }

  List<TransactionRecord> _mergeTransactions(
    List<TransactionRecord> remoteTransactions,
    List<TransactionRecord> pending,
  ) {
    final pendingOperationIds = pending
        .map((transaction) => transaction.clientOperationId)
        .whereType<String>()
        .toSet();
    final merged = remoteTransactions
        .where(
          (transaction) =>
              !pendingOperationIds.contains(transaction.clientOperationId),
        )
        .toList();
    merged.addAll(pending);
    merged.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return merged;
  }

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
    final clientOperationId = map['clientOperationId']?.toString();
    if (clientOperationId != null && clientOperationId.isNotEmpty) {
      _remoteUuidByOperationId[clientOperationId] = uuid;
    }
    return TransactionRecord()
      ..uuid = uuid
      ..ledgerUuid = map['ledgerUuid'].toString()
      ..type = (map['type'] as num?)?.toInt() ?? 0
      ..payerPersonUuid = map['payerPersonUuid']?.toString()
      ..clientOperationId = clientOperationId
      ..version = _versionByUuid[uuid]
      ..amount = (map['amount'] as num?)?.toDouble() ?? 0
      ..currencyCode = map['currencyCode'].toString()
      ..category = map['category'].toString()
      ..note = map['note']?.toString() ?? ''
      ..personUuids = (map['personUuids'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList()
      ..createdAt =
          DateTime.tryParse(map['happenedAt']?.toString() ?? '') ??
          DateTime.now()
      ..pendingSync = false
      ..syncError = null;
  }
}

class _TransactionPage {
  const _TransactionPage({required this.total, required this.records});

  final int total;
  final List<TransactionRecord> records;
}
