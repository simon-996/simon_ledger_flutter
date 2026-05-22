import '../../../../core/models/transaction_record.dart';

typedef LedgerStatsMap = Map<String, Map<String, double>>;

LedgerStatsMap calculateLedgerStats({
  required Iterable<String> ledgerUuids,
  required Iterable<TransactionRecord> transactions,
}) {
  final stats = <String, Map<String, double>>{};

  for (final ledgerUuid in ledgerUuids) {
    stats[ledgerUuid] = {'expense': 0, 'income': 0, 'balance': 0};
  }

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
    ledgerStats['balance'] = income - expense;
  }

  return stats;
}
