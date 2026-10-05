import 'dart:async';

import '../database/database_service.dart';
import '../models/conflict_record.dart';
import '../models/transaction_record.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../services/conflict_coordinator.dart';
import '../services/conflict_snapshot_codec.dart';
import '../services/sync_identity_resolver.dart';

abstract class TransactionRepository {
  Future<List<TransactionRecord>> getCachedTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  });

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

  Future<TransactionSyncResult> syncPendingTransactions(String ledgerUuid);
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
  Future<List<TransactionRecord>> getCachedTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) {
    return _db.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );
  }

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

  @override
  Future<TransactionSyncResult> syncPendingTransactions(
    String ledgerUuid,
  ) async {
    return const TransactionSyncResult(synced: 0);
  }
}

class RemoteTransactionRepository implements TransactionRepository {
  RemoteTransactionRepository({
    required ApiClient apiClient,
    required DatabaseService database,
    SyncIdentityResolver? identityResolver,
    ConflictCoordinator? conflictCoordinator,
    ConflictSnapshotCodec? conflictCodec,
  }) : _apiClient = apiClient,
       _db = database,
       _identityResolver = identityResolver ?? SyncIdentityResolver(database),
       _conflictCoordinator = conflictCoordinator,
       _conflictCodec = conflictCodec;

  static const int _pageSize = 100;

  final ApiClient _apiClient;
  final DatabaseService _db;
  final SyncIdentityResolver _identityResolver;
  final ConflictCoordinator? _conflictCoordinator;
  final ConflictSnapshotCodec? _conflictCodec;
  final Map<String, Future<TransactionSyncResult>> _activeSyncs = {};
  Future<void> _cacheMutation = Future<void>.value();
  final Set<String> _syncAgain = {};

  // Keep short cache mutations ordered; network requests remain outside this
  // queue so undo can hide a transaction immediately while an upload is waiting.
  Future<T> _mutateCache<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _cacheMutation = _cacheMutation.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  Future<List<TransactionRecord>> getCachedTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) {
    return _db.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) async {
    final localTransactions = await _db.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: includeDeleted,
    );
    if (await _isLocalOnlyLedger(ledgerUuid)) {
      return localTransactions;
    }

    try {
      await syncPendingTransactions(ledgerUuid);
      final remoteTransactions = await _fetchRemoteTransactions(ledgerUuid);
      final latestLocalTransactions = await _db.getTransactionsForLedger(
        ledgerUuid,
        includeDeleted: true,
      );
      final latestPending = latestLocalTransactions
          .where((transaction) => transaction.pendingSync)
          .toList();

      return _mergeTransactions(
        remoteTransactions,
        latestPending,
      ).where((record) => includeDeleted || !record.isDeleted).toList();
    } catch (_) {
      return _db.getTransactionsForLedger(
        ledgerUuid,
        includeDeleted: includeDeleted,
      );
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
    if (await _isLocalOnlyLedger(transaction.ledgerUuid)) {
      await _db.saveTransaction(
        transaction
          ..pendingSync = false
          ..syncError = null,
      );
      return;
    }
    final local = _localPendingTransaction(transaction);
    await _mutateCache(() => _db.saveTransaction(local));
    transaction
      ..clientOperationId = local.clientOperationId
      ..pendingSync = local.pendingSync
      ..syncError = local.syncError;
    if (_activeSyncs.containsKey(transaction.ledgerUuid)) {
      _syncAgain.add(transaction.ledgerUuid);
    }
    unawaited(syncPendingTransactions(transaction.ledgerUuid));
  }

  @override
  Future<TransactionSyncResult> syncPendingTransactions(String ledgerUuid) {
    final active = _activeSyncs[ledgerUuid];
    if (active != null) return active;
    final operation = _drainPendingTransactions(ledgerUuid);
    _activeSyncs[ledgerUuid] = operation;
    operation.then<void>(
      (_) => _activeSyncs.remove(ledgerUuid),
      onError: (Object error, StackTrace stack) {
        _activeSyncs.remove(ledgerUuid);
      },
    );
    return operation;
  }

  Future<TransactionSyncResult> _drainPendingTransactions(
    String ledgerUuid,
  ) async {
    var synced = 0;
    Object? error;
    do {
      _syncAgain.remove(ledgerUuid);
      final pass = await _syncPendingTransactions(ledgerUuid);
      synced += pass.synced;
      error ??= pass.error;
    } while (_syncAgain.contains(ledgerUuid));
    return TransactionSyncResult(synced: synced, error: error);
  }

  Future<TransactionSyncResult> _syncPendingTransactions(
    String ledgerUuid,
  ) async {
    if (await _isLocalOnlyLedger(ledgerUuid)) {
      return const TransactionSyncResult(synced: 0);
    }
    final transactions = await _db.getTransactionsForLedger(
      ledgerUuid,
      includeDeleted: true,
    );
    final pending = transactions
        .where((transaction) => transaction.pendingSync)
        .toList();
    var synced = 0;
    Object? firstError;

    for (final transaction in pending) {
      try {
        if (transaction.isDeleted) {
          await _deletePendingTransaction(transaction);
        } else {
          await _uploadPendingTransaction(transaction);
        }
        synced += 1;
      } catch (error) {
        final operation = transaction.isDeleted
            ? ConflictOperation.delete
            : ConflictOperation.update;
        if (await _captureTransactionConflict(error, transaction, operation)) {
          transaction
            ..pendingSync = false
            ..syncError = null;
          await _db.saveTransaction(transaction);
          continue;
        }
        firstError ??= error;
        await _mutateCache(() async {
          final records = await _db.getTransactionsForLedger(
            ledgerUuid,
            includeDeleted: true,
          );
          var latest = records
              .where((record) => record.uuid == transaction.uuid)
              .firstOrNull;
          if (latest != null &&
              latest.isDeleted &&
              !_hasRemoteIdentity(latest) &&
              latest.clientOperationId != null) {
            final operationId = latest.clientOperationId;
            latest =
                records
                    .where(
                      (record) =>
                          record.clientOperationId == operationId &&
                          _hasRemoteIdentity(record),
                    )
                    .firstOrNull ??
                latest;
          }
          if (latest == null) return;
          // A create may have been accepted before its response was lost.
          // Retain its deletion intent and stable idempotency key for retry.
          latest
            ..pendingSync = true
            ..syncError = error.toString();
          await _db.saveTransaction(latest);
        });
      }
    }

    return TransactionSyncResult(synced: synced, error: firstError);
  }

  Future<void> _uploadPendingTransaction(TransactionRecord transaction) async {
    final remoteLedgerUuid = await _identityResolver.resolveLedgerUuid(
      transaction.ledgerUuid,
    );
    final remotePayerPersonUuid = transaction.payerPersonUuid == null
        ? null
        : await _identityResolver.resolvePersonUuid(
            transaction.payerPersonUuid!,
          );
    final remotePersonUuids = await _identityResolver.resolvePersonUuids(
      transaction.personUuids,
    );
    final data = {
      'type': transaction.type,
      'payerPersonUuid': remotePayerPersonUuid,
      'amount': transaction.amount,
      'currencyCode': transaction.currencyCode,
      'category': transaction.category,
      'note': transaction.note,
      'happenedAt': transaction.createdAt.toIso8601String(),
      'clientOperationId': transaction.clientOperationId ?? transaction.uuid,
      'personUuids': remotePersonUuids,
    };

    final remoteUuid = _hasRemoteIdentity(transaction)
        ? transaction.uuid
        : null;
    final version = transaction.version;
    if (remoteUuid == null) {
      final saved = await _apiClient.post<TransactionRecord>(
        '/api/ledgers/$remoteLedgerUuid/transactions',
        data: data,
        idempotencyKey: transaction.clientOperationId ?? transaction.uuid,
        fromJson: _transactionFromJson,
      );
      if (await _saveSyncedTransaction(transaction, saved)) {
        await _deletePendingTransaction(saved);
      }
      return;
    }

    final saved = await _apiClient.put<TransactionRecord>(
      '/api/ledgers/$remoteLedgerUuid/transactions/$remoteUuid',
      data: {...data, 'version': version},
      idempotencyKey: 'update-transaction-$remoteUuid-$version',
      fromJson: _transactionFromJson,
    );
    if (await _saveSyncedTransaction(transaction, saved)) {
      await _deletePendingTransaction(saved);
    }
  }

  @override
  Future<void> deleteTransaction(String ledgerUuid, String uuid) async {
    final localOnly = await _isLocalOnlyLedger(ledgerUuid);
    await _mutateCache(() async {
      final records = await _db.getTransactionsForLedger(
        ledgerUuid,
        includeDeleted: true,
      );
      final source = records.where((record) => record.uuid == uuid).firstOrNull;
      if (source == null) return;
      final operationId = source.clientOperationId ?? source.uuid;
      // Upload can replace a local uuid. Retain aliases and delete every current
      // representation of the same operation, including the returned cloud row.
      for (final record in records.where(
        (record) =>
            record.uuid == uuid ||
            (record.clientOperationId != null &&
                record.clientOperationId == operationId),
      )) {
        final pendingDelete =
            !localOnly && (record.pendingSync || _hasRemoteIdentity(record));
        record
          ..isDeleted = true
          ..pendingSync = pendingDelete
          ..syncError = null;
        await _db.saveTransaction(record);
      }
    });
  }

  Future<void> _deletePendingTransaction(TransactionRecord transaction) async {
    final remoteLedgerUuid = await _identityResolver.resolveLedgerUuid(
      transaction.ledgerUuid,
    );
    final remoteUuid = _hasRemoteIdentity(transaction)
        ? transaction.uuid
        : null;
    final version = transaction.version;
    if (remoteUuid == null) {
      // Replay a cancelled create with the same idempotency key, then delete the
      // returned identity. This also covers a server-accepted, lost response.
      await _uploadPendingTransaction(transaction);
      return;
    }

    await _apiClient.deleteVoid(
      '/api/ledgers/$remoteLedgerUuid/transactions/$remoteUuid',
      data: {'version': version},
      idempotencyKey: 'delete-transaction-$remoteUuid-$version',
    );
    transaction.version = version + 1;
    await _saveDeletedTransaction(transaction);
  }

  Future<bool> _captureTransactionConflict(
    Object error,
    TransactionRecord transaction,
    ConflictOperation operation,
  ) async {
    final coordinator = _conflictCoordinator;
    final codec = _conflictCodec;
    if (coordinator == null ||
        codec == null ||
        error is! ApiException ||
        !error.isConflict) {
      return false;
    }
    return coordinator.capture(
      error: error,
      operation: operation,
      ledgerUuid: transaction.ledgerUuid,
      localUuid: transaction.uuid,
      localSnapshot: codec.transactionSnapshot(transaction),
    );
  }

  static bool _hasRemoteIdentity(TransactionRecord transaction) {
    // AI drafts also use 32-digit hex ids. Until create returns a server uuid,
    // the local uuid equals the stable client operation id (including old caches).
    return transaction.uuid != transaction.clientOperationId &&
        RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(transaction.uuid);
  }

  Future<bool> _isLocalOnlyLedger(String ledgerUuid) async {
    final ledgers = await _db.getAllLedgers(includeDeleted: true);
    final ledger = ledgers
        .where((ledger) => ledger.uuid == ledgerUuid)
        .firstOrNull;
    return ledger?.isLocalOnly == true;
  }

  Future<List<TransactionRecord>> _fetchRemoteTransactions(
    String ledgerUuid,
  ) async {
    final remoteLedgerUuid = await _identityResolver.resolveLedgerUuid(
      ledgerUuid,
    );
    final all = <TransactionRecord>[];
    var page = 1;
    var total = 0;

    do {
      final pageData = await _getTransactionPage(remoteLedgerUuid, page);
      total = pageData.total;
      all.addAll(pageData.records);
      if (pageData.records.isEmpty) {
        break;
      }
      page += 1;
    } while (all.length < total);

    await _mutateCache(() async {
      final cached = await _db.getTransactionsForLedger(
        ledgerUuid,
        includeDeleted: true,
      );
      for (final transaction in all) {
        final current = cached
            .where((record) => record.uuid == transaction.uuid)
            .firstOrNull;
        if (current?.pendingSync == true) continue;
        final cancelledAlias = cached
            .where(
              (record) =>
                  record.isDeleted &&
                  record.pendingSync &&
                  transaction.clientOperationId != null &&
                  record.clientOperationId == transaction.clientOperationId,
            )
            .firstOrNull;
        if (cancelledAlias != null) {
          transaction
            ..ledgerUuid = ledgerUuid
            ..localAccountUuid =
                cancelledAlias.localAccountUuid ?? _db.scope.accountUuid
            ..isDeleted = true
            ..pendingSync = true;
          await _db.saveTransaction(transaction);
          if (cancelledAlias.uuid != transaction.uuid) {
            await _db.saveTransaction(
              cancelledAlias
                ..pendingSync = false
                ..syncError = null,
            );
          }
          continue;
        }
        if (current != null &&
            current.isDeleted &&
            current.version >= transaction.version) {
          transaction.isDeleted = true;
          continue;
        }
        transaction.ledgerUuid = ledgerUuid;
        transaction.localAccountUuid = _db.scope.accountUuid;
        await _db.saveTransaction(transaction);
      }
    });
    return all;
  }

  TransactionRecord _localPendingTransaction(TransactionRecord transaction) {
    final clientOperationId =
        transaction.clientOperationId ??
        (_hasRemoteIdentity(transaction) ? null : transaction.uuid);
    return transaction
      ..clientOperationId = clientOperationId
      ..localAccountUuid = transaction.localAccountUuid ?? _db.scope.accountUuid
      ..pendingSync = true
      ..syncError = null;
  }

  Future<bool> _saveSyncedTransaction(
    TransactionRecord local,
    TransactionRecord remote,
  ) => _mutateCache(() async {
    final cached = (await _db.getTransactionsForLedger(
      local.ledgerUuid,
      includeDeleted: true,
    )).where((record) => record.uuid == local.uuid).firstOrNull;
    final cancelled = cached?.isDeleted == true;
    final newerEdit =
        !cancelled && cached != null && !_sameContent(local, cached);
    if (newerEdit) {
      remote
        ..amount = cached.amount
        ..type = cached.type
        ..payerPersonUuid = cached.payerPersonUuid
        ..currencyCode = cached.currencyCode
        ..category = cached.category
        ..note = cached.note
        ..personUuids = List.of(cached.personUuids)
        ..createdAt = cached.createdAt;
    }
    if (local.uuid != remote.uuid) {
      await _db.saveTransaction(
        local
          ..isDeleted = true
          ..pendingSync = false
          ..syncError = null,
      );
    }
    await _db.saveTransaction(
      remote
        ..ledgerUuid = local.ledgerUuid
        ..localAccountUuid = local.localAccountUuid ?? _db.scope.accountUuid
        ..clientOperationId = local.clientOperationId
        ..isDeleted = cancelled
        ..pendingSync = cancelled || newerEdit
        ..syncError = null,
    );
    return cancelled;
  });

  bool _sameContent(TransactionRecord left, TransactionRecord right) =>
      left.amount == right.amount &&
      left.type == right.type &&
      left.payerPersonUuid == right.payerPersonUuid &&
      left.currencyCode == right.currencyCode &&
      left.category == right.category &&
      left.note == right.note &&
      left.createdAt == right.createdAt &&
      left.personUuids.length == right.personUuids.length &&
      left.personUuids.every(right.personUuids.contains);

  Future<void> _saveDeletedTransaction(TransactionRecord transaction) =>
      _mutateCache(
        () => _db.saveTransaction(
          transaction
            ..isDeleted = true
            ..pendingSync = false
            ..syncError = null,
        ),
      );

  List<TransactionRecord> _mergeTransactions(
    List<TransactionRecord> remoteTransactions,
    List<TransactionRecord> pending,
  ) {
    final pendingOperationIds = pending
        .map((transaction) => transaction.clientOperationId)
        .whereType<String>()
        .toSet();
    final pendingUuids = pending.map((record) => record.uuid).toSet();
    final merged = remoteTransactions
        .where(
          (transaction) =>
              !pendingUuids.contains(transaction.uuid) &&
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
    final clientOperationId = map['clientOperationId']?.toString();
    final creatorUuid = map['createdByUserUuid']?.toString();
    final deletedCreator =
        map.containsKey('createdByUserUuid') && creatorUuid == null;
    return TransactionRecord()
      ..uuid = uuid
      ..ledgerUuid = map['ledgerUuid'].toString()
      ..type = (map['type'] as num?)?.toInt() ?? 0
      ..payerPersonUuid = map['payerPersonUuid']?.toString()
      ..clientOperationId = clientOperationId
      ..version = (map['version'] as num?)?.toInt() ?? 1
      ..amount = (map['amount'] as num?)?.toDouble() ?? 0
      ..currencyCode = map['currencyCode'].toString()
      ..category = map['category'].toString()
      ..note = map['note']?.toString() ?? ''
      ..personUuids = (map['personUuids'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList()
      ..createdByUserUuid = creatorUuid
      ..createdByNickname = deletedCreator
          ? '已注销用户'
          : map['createdByNickname']?.toString()
      ..createdByAvatar = deletedCreator
          ? null
          : map['createdByAvatar']?.toString()
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
