import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import 'ledger_stats_calculator.dart';

part 'ledger_stats_provider.g.dart';

@riverpod
class LedgerStats extends _$LedgerStats {
  @override
  Future<Map<String, Map<String, double>>> build() async {
    await ref.watch(authTokenProvider.future);
    final ledgerRepository = ref.watch(ledgerRepositoryProvider);
    final transactionRepository = ref.watch(transactionRepositoryProvider);
    final ledgers = await ledgerRepository.getCachedLedgers();
    final transactionsByLedger = await Future.wait(
      ledgers.map(
        (ledger) =>
            transactionRepository.getCachedTransactionsForLedger(ledger.uuid),
      ),
    );

    return calculateLedgerStats(
      ledgerUuids: ledgers.map((ledger) => ledger.uuid),
      ledgersByUuid: {for (final ledger in ledgers) ledger.uuid: ledger},
      transactions: transactionsByLedger.expand((transactions) => transactions),
    );
  }

  void refresh() {
    ref.invalidateSelf();
  }
}
