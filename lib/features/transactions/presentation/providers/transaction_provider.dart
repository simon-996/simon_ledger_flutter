import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/repositories/transaction_repository.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';

part 'transaction_provider.g.dart';

class LedgerSyncStatus {
  const LedgerSyncStatus({
    required this.ledgerPendingCount,
    required this.personPendingCount,
    required this.transactionPendingCount,
    required this.ledgerFailedCount,
    required this.personFailedCount,
    required this.transactionFailedCount,
  });

  final int ledgerPendingCount;
  final int personPendingCount;
  final int transactionPendingCount;
  final int ledgerFailedCount;
  final int personFailedCount;
  final int transactionFailedCount;

  int get pendingCount =>
      ledgerPendingCount + personPendingCount + transactionPendingCount;
  int get failedCount =>
      ledgerFailedCount + personFailedCount + transactionFailedCount;

  bool get hasPending => pendingCount > 0;
  bool get hasFailed => failedCount > 0;
}

final ledgerSyncStatusProvider =
    FutureProvider.family<LedgerSyncStatus, String>((ref, ledgerUuid) async {
      final database = ref.watch(databaseProvider);
      final ledgers = await database.getAllLedgers(includeDeleted: true);
      final ledger = ledgers
          .where((ledger) => ledger.uuid == ledgerUuid)
          .firstOrNull;
      final ledgerPending =
          ledger != null &&
          (ledger.shouldUploadToCloud || ledger.pendingSync) &&
          !ledger.isLocalOnly;
      final people = await database.getAllPeople(includeDeleted: true);
      final pendingPeople = people.where((person) {
        return person.pendingSync && person.pendingLedgerUuid == ledgerUuid;
      }).toList();
      final transactions = await database.getTransactionsForLedger(
        ledgerUuid,
        includeDeleted: true,
      );
      final pending = transactions.where((transaction) {
        return transaction.pendingSync;
      }).toList();
      final failedCount = pending.where((transaction) {
        final error = transaction.syncError;
        return error != null && error.isNotEmpty;
      }).length;
      return LedgerSyncStatus(
        ledgerPendingCount: ledgerPending ? 1 : 0,
        personPendingCount: pendingPeople.length,
        transactionPendingCount: pending.length,
        ledgerFailedCount: ledgerPending && ledger.syncError?.isNotEmpty == true
            ? 1
            : 0,
        personFailedCount: pendingPeople.where((person) {
          return person.syncError?.isNotEmpty == true;
        }).length,
        transactionFailedCount: failedCount,
      );
    });

@riverpod
class TransactionNotifier extends _$TransactionNotifier {
  @override
  Future<List<TransactionRecord>> build(String ledgerUuid) async {
    await ref.watch(authTokenProvider.future);
    final repository = ref.watch(transactionRepositoryProvider);
    if (repository is! RemoteTransactionRepository) {
      return repository.getTransactionsForLedger(ledgerUuid);
    }

    var disposed = false;
    ref.onDispose(() => disposed = true);
    unawaited(_refreshRemote(repository, isDisposed: () => disposed));
    return repository.getCachedTransactionsForLedger(ledgerUuid);
  }

  Future<void> _refreshRemote(
    RemoteTransactionRepository repository, {
    required bool Function() isDisposed,
  }) async {
    final transactions = await repository.getTransactionsForLedger(ledgerUuid);
    if (isDisposed()) return;
    state = AsyncValue.data(transactions);
    ref.invalidate(ledgerSyncStatusProvider(ledgerUuid));
    ref.invalidate(ledgerStatsProvider);
  }

  Future<void> addTransaction(TransactionRecord transaction) async {
    final repository = ref.read(transactionRepositoryProvider);
    await repository.saveTransaction(transaction);

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data([transaction, ...current]);
    }

    // Invalidate ledger stats so the UI updates
    ref.invalidate(ledgerSyncStatusProvider(ledgerUuid));
    ref.invalidate(ledgerStatsProvider);
  }

  Future<void> updateTransaction(TransactionRecord transaction) async {
    final repository = ref.read(transactionRepositoryProvider);
    await repository.saveTransaction(transaction);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(_upsertTransaction(current, transaction));
    }

    ref.invalidate(ledgerSyncStatusProvider(ledgerUuid));
    ref.invalidate(ledgerStatsProvider);
  }

  Future<void> deleteTransaction(String uuid) async {
    final repository = ref.read(transactionRepositoryProvider);
    await repository.deleteTransaction(ledgerUuid, uuid);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.where((transaction) => transaction.uuid != uuid).toList(),
      );
    }

    ref.invalidate(ledgerSyncStatusProvider(ledgerUuid));
    ref.invalidate(ledgerStatsProvider);
  }

  Future<void> syncPending() async {
    final repository = ref.read(transactionRepositoryProvider);
    await repository.syncPendingTransactions(ledgerUuid);

    ref.invalidate(ledgerSyncStatusProvider(ledgerUuid));
    ref.invalidate(ledgerStatsProvider);
    ref.invalidateSelf();
  }

  List<TransactionRecord> _upsertTransaction(
    List<TransactionRecord> transactions,
    TransactionRecord transaction,
  ) {
    final items = List<TransactionRecord>.from(transactions);
    final index = items.indexWhere((item) => item.uuid == transaction.uuid);
    if (index == -1) {
      items.insert(0, transaction);
    } else {
      items[index] = transaction;
    }
    items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return items;
  }
}
