import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';

part 'transaction_provider.g.dart';

@riverpod
class TransactionNotifier extends _$TransactionNotifier {
  @override
  Future<List<TransactionRecord>> build(String ledgerUuid) async {
    return _fetchTransactions();
  }

  Future<List<TransactionRecord>> _fetchTransactions() async {
    final db = ref.read(databaseProvider);
    return await db.getTransactionsForLedger(ledgerUuid);
  }

  Future<void> addTransaction(TransactionRecord transaction) async {
    final db = ref.read(databaseProvider);
    await db.saveTransaction(transaction);
    
    // Invalidate ledger stats so the UI updates
    ref.invalidate(ledgerStatsProvider);
    // Refresh local list
    ref.invalidateSelf();
  }

  Future<void> updateTransaction(TransactionRecord transaction) async {
    final db = ref.read(databaseProvider);
    await db.saveTransaction(transaction);
    
    ref.invalidate(ledgerStatsProvider);
    ref.invalidateSelf();
  }

  Future<void> deleteTransaction(String uuid) async {
    final db = ref.read(databaseProvider);
    await db.deleteTransaction(uuid);
    
    ref.invalidate(ledgerStatsProvider);
    ref.invalidateSelf();
  }
}
