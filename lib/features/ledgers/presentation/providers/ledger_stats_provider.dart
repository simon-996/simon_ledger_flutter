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
      stats[ledger.uuid] = {'expense': 0, 'income': 0, 'balance': 0};
    }

    final transactions = await db.getTransactionsForLedgers(
      ledgers.map((ledger) => ledger.uuid).toList(),
    );

    for (final transaction in transactions) {
      final ledgerStats = stats[transaction.ledgerUuid];
      if (ledgerStats == null) continue;

      if (transaction.type == 0) {
        ledgerStats['expense'] = ledgerStats['expense']! + transaction.amount;
      } else {
        ledgerStats['income'] = ledgerStats['income']! + transaction.amount;
      }
    }

    for (final ledgerStats in stats.values) {
      final income = ledgerStats['income']!;
      final expense = ledgerStats['expense']!;
      final balance = income - expense;
      ledgerStats['balance'] = balance;
    }

    return stats;
  }

  void refresh() {
    ref.invalidateSelf();
  }
}
