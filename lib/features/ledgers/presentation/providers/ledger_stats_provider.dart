import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import 'ledger_stats_calculator.dart';

part 'ledger_stats_provider.g.dart';

@riverpod
class LedgerStats extends _$LedgerStats {
  @override
  Future<Map<String, Map<String, double>>> build() async {
    final ledgerRepository = ref.read(ledgerRepositoryProvider);
    final transactionRepository = ref.read(transactionRepositoryProvider);
    final ledgers = await ledgerRepository.getAllLedgers();
    final transactions = await transactionRepository.getTransactionsForLedgers(
      ledgers.map((ledger) => ledger.uuid).toList(),
    );

    return calculateLedgerStats(
      ledgerUuids: ledgers.map((ledger) => ledger.uuid),
      transactions: transactions,
    );
  }

  void refresh() {
    ref.invalidateSelf();
  }
}
