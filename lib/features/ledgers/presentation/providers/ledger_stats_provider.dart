import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';

part 'ledger_stats_provider.g.dart';

@riverpod
class LedgerStats extends _$LedgerStats {
  @override
  Future<Map<String, Map<String, double>>> build() async {
    final db = ref.read(databaseProvider);
    final ledgers = await db.getAllLedgers();
    
    final Map<String, Map<String, double>> stats = {};
    for (final ledger in ledgers) {
      final transactions = await db.getTransactionsForLedger(ledger.uuid);
      final expense = transactions.where((t) => t.type == 0).fold(0.0, (sum, t) => sum + t.amount);
      final income = transactions.where((t) => t.type == 1).fold(0.0, (sum, t) => sum + t.amount);
      final balance = income - expense;
      stats[ledger.uuid] = {
        'expense': expense, 
        'income': income,
        'balance': balance,
      };
    }
    
    return stats;
  }

  void refresh() {
    ref.invalidateSelf();
  }
}
