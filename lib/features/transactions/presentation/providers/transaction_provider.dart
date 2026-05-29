import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';

part 'transaction_provider.g.dart';

class LedgerSyncStatus {
  const LedgerSyncStatus({
    required this.pendingCount,
    required this.failedCount,
  });

  final int pendingCount;
  final int failedCount;

  bool get hasPending => pendingCount > 0;
  bool get hasFailed => failedCount > 0;
}

final ledgerSyncStatusProvider =
    FutureProvider.family<LedgerSyncStatus, String>((ref, ledgerUuid) async {
      final database = ref.watch(databaseProvider);
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
        pendingCount: pending.length,
        failedCount: failedCount,
      );
    });

@riverpod
class TransactionNotifier extends _$TransactionNotifier {
  @override
  Future<List<TransactionRecord>> build(String ledgerUuid) async {
    await ref.watch(authTokenProvider.future);
    final repository = ref.watch(transactionRepositoryProvider);
    return await repository.getTransactionsForLedger(ledgerUuid);
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
