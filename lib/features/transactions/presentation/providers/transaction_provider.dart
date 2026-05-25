import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';

part 'transaction_provider.g.dart';

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
    ref.invalidate(ledgerStatsProvider);
    // Refresh local list
    ref.invalidateSelf();
  }

  Future<void> updateTransaction(TransactionRecord transaction) async {
    final repository = ref.read(transactionRepositoryProvider);
    await repository.saveTransaction(transaction);

    ref.invalidate(ledgerStatsProvider);
    ref.invalidateSelf();
  }

  Future<void> deleteTransaction(String uuid) async {
    final repository = ref.read(transactionRepositoryProvider);
    await repository.deleteTransaction(ledgerUuid, uuid);

    ref.invalidate(ledgerStatsProvider);
    ref.invalidateSelf();
  }
}
