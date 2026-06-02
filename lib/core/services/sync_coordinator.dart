import '../database/database_service.dart';
import '../repositories/ledger_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/transaction_repository.dart';
import 'sync_overview_service.dart';

class SyncAllPendingResult {
  const SyncAllPendingResult({
    required this.attemptedCount,
    required this.syncedCount,
    required this.failedCount,
    this.error,
  });

  const SyncAllPendingResult.none()
    : attemptedCount = 0,
      syncedCount = 0,
      failedCount = 0,
      error = null;

  final int attemptedCount;
  final int syncedCount;
  final int failedCount;
  final Object? error;

  bool get attempted => attemptedCount > 0;

  bool get changed => attempted;

  bool get hasError => failedCount > 0 || error != null;
}

class SyncCoordinator {
  SyncCoordinator({
    required LedgerRepository ledgerRepository,
    required PersonRepository personRepository,
    required TransactionRepository transactionRepository,
    required DatabaseService database,
    SyncOverviewService? syncOverviewService,
    Duration retryDelay = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _ledgerRepository = ledgerRepository,
       _personRepository = personRepository,
       _transactionRepository = transactionRepository,
       _database = database,
       _syncOverviewService =
           syncOverviewService ?? SyncOverviewService(database),
       _retryDelay = retryDelay,
       _now = now ?? DateTime.now;

  final LedgerRepository _ledgerRepository;
  final PersonRepository _personRepository;
  final TransactionRepository _transactionRepository;
  final DatabaseService _database;
  final SyncOverviewService _syncOverviewService;
  final Duration _retryDelay;
  final DateTime Function() _now;
  final Map<String, Future<TransactionSyncResult>> _ledgerSyncs = {};
  final Map<String, DateTime> _ledgerRetryAfter = {};
  Future<SyncAllPendingResult>? _allPendingSync;
  DateTime? _allPendingRetryAfter;

  Future<TransactionSyncResult> syncLedger(
    String ledgerUuid, {
    bool force = false,
  }) {
    return _startLedgerSync(ledgerUuid, force: force, syncLedgerWrites: true);
  }

  Future<bool> syncAllPending({bool force = false}) async {
    final result = await syncAllPendingResult(force: force);
    return result.changed;
  }

  Future<SyncAllPendingResult> syncAllPendingResult({bool force = false}) {
    final current = _allPendingSync;
    if (current != null) return current;
    if (!force && !_canRetry(_allPendingRetryAfter)) {
      return Future.value(const SyncAllPendingResult.none());
    }

    late final Future<SyncAllPendingResult> sync;
    sync = _syncAllPendingNow(force: force).whenComplete(() {
      if (identical(_allPendingSync, sync)) {
        _allPendingSync = null;
      }
    });
    _allPendingSync = sync;
    return sync;
  }

  Future<SyncAllPendingResult> _syncAllPendingNow({required bool force}) async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    final people = await _database.getAllPeople(includeDeleted: true);
    final transactions = await _database.getTransactionsForLedgers(
      ledgers.map((ledger) => ledger.uuid).toList(),
      includeDeleted: true,
    );
    final syncableLedgerUuids = {
      for (final ledger in ledgers)
        if (ledger.shouldUploadToCloud || ledger.isCloudManaged) ledger.uuid,
    };
    final ledgerUuids = <String>{
      for (final ledger in ledgers)
        if (syncableLedgerUuids.contains(ledger.uuid) &&
            (ledger.pendingSync || ledger.shouldUploadToCloud))
          ledger.uuid,
      for (final person in people)
        if (person.pendingSync &&
            syncableLedgerUuids.contains(person.pendingLedgerUuid))
          person.pendingLedgerUuid!,
      for (final transaction in transactions)
        if (transaction.pendingSync &&
            syncableLedgerUuids.contains(transaction.ledgerUuid))
          transaction.ledgerUuid,
    };
    if (ledgerUuids.isEmpty) return const SyncAllPendingResult.none();

    try {
      await _ledgerRepository.syncPendingWrites();
      var syncedCount = 0;
      var failedCount = 0;
      Object? firstError;
      for (final ledgerUuid in ledgerUuids) {
        final result = await _startLedgerSync(
          ledgerUuid,
          force: force,
          syncLedgerWrites: false,
        );
        syncedCount += result.synced;
        if (result.error != null) {
          failedCount += 1;
          firstError ??= result.error;
        }
      }
      _allPendingRetryAfter = null;
      if (firstError == null) {
        await _syncOverviewService.markSuccessfulSync(_now());
      }
      return SyncAllPendingResult(
        attemptedCount: ledgerUuids.length,
        syncedCount: syncedCount,
        failedCount: failedCount,
        error: firstError,
      );
    } catch (_) {
      _allPendingRetryAfter = _now().add(_retryDelay);
      rethrow;
    }
  }

  Future<TransactionSyncResult> _startLedgerSync(
    String ledgerUuid, {
    bool force = false,
    required bool syncLedgerWrites,
  }) {
    final current = _ledgerSyncs[ledgerUuid];
    if (current != null) return current;
    if (!force && !_canRetry(_ledgerRetryAfter[ledgerUuid])) {
      return Future.value(const TransactionSyncResult(synced: 0));
    }

    late final Future<TransactionSyncResult> sync;
    sync = _syncLedgerNow(ledgerUuid, syncLedgerWrites: syncLedgerWrites)
        .whenComplete(() {
          if (identical(_ledgerSyncs[ledgerUuid], sync)) {
            _ledgerSyncs.remove(ledgerUuid);
          }
        });
    _ledgerSyncs[ledgerUuid] = sync;
    return sync;
  }

  Future<TransactionSyncResult> _syncLedgerNow(
    String ledgerUuid, {
    required bool syncLedgerWrites,
  }) async {
    try {
      if (syncLedgerWrites) {
        await _ledgerRepository.syncPendingWrites(ledgerUuid: ledgerUuid);
      }
      await _personRepository.syncPendingPeople(ledgerUuid);
      final result = await _transactionRepository.syncPendingTransactions(
        ledgerUuid,
      );
      if (result.error != null) {
        _ledgerRetryAfter[ledgerUuid] = _now().add(_retryDelay);
        return result;
      }
      _ledgerRetryAfter.remove(ledgerUuid);
      await _syncOverviewService.markSuccessfulSync(_now());
      return result;
    } catch (_) {
      _ledgerRetryAfter[ledgerUuid] = _now().add(_retryDelay);
      rethrow;
    }
  }

  bool _canRetry(DateTime? retryAfter) {
    return retryAfter == null || !_now().isBefore(retryAfter);
  }
}
