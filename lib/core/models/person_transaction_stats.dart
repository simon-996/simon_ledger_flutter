import 'transaction_record.dart';

class PersonTransactionStats {
  PersonTransactionStats({
    required this.personBalances,
    required this.settlements,
  });

  final Map<String, double> personBalances;
  final List<PersonSettlement> settlements;
}

class PersonSettlement {
  const PersonSettlement({
    required this.fromPersonUuid,
    required this.toPersonUuid,
    required this.amount,
  });

  final String fromPersonUuid;
  final String toPersonUuid;
  final double amount;
}

PersonTransactionStats calculatePersonTransactionStats(
  Iterable<TransactionRecord> transactions, {
  double Function(TransactionRecord transaction)? amountOf,
}) {
  final personBalances = <String, double>{};
  final netSettlementMap = <String, double>{};

  for (final transaction in transactions) {
    if (transaction.personUuids.isEmpty) continue;

    final amount = amountOf?.call(transaction) ?? transaction.amount;
    final splitAmount = amount / transaction.personUuids.length;

    if (transaction.type == 1) {
      for (final personUuid in transaction.personUuids) {
        personBalances[personUuid] =
            (personBalances[personUuid] ?? 0) + splitAmount;
      }
      continue;
    }

    final payerPersonUuid = transaction.payerPersonUuid;
    if (payerPersonUuid == null || payerPersonUuid.isEmpty) {
      for (final personUuid in transaction.personUuids) {
        personBalances[personUuid] =
            (personBalances[personUuid] ?? 0) - splitAmount;
      }
      continue;
    }

    personBalances[payerPersonUuid] =
        (personBalances[payerPersonUuid] ?? 0) + amount;
    for (final personUuid in transaction.personUuids) {
      personBalances[personUuid] =
          (personBalances[personUuid] ?? 0) - splitAmount;
      if (personUuid == payerPersonUuid) continue;
      _addNetSettlement(
        netSettlementMap,
        fromPersonUuid: personUuid,
        toPersonUuid: payerPersonUuid,
        amount: splitAmount,
      );
    }
  }

  final settlements =
      netSettlementMap.entries.where((entry) => entry.value > 0.004).map((
        entry,
      ) {
        final parts = entry.key.split('->');
        return PersonSettlement(
          fromPersonUuid: parts[0],
          toPersonUuid: parts[1],
          amount: entry.value,
        );
      }).toList()..sort((left, right) => right.amount.compareTo(left.amount));

  return PersonTransactionStats(
    personBalances: personBalances,
    settlements: settlements,
  );
}

void _addNetSettlement(
  Map<String, double> settlementMap, {
  required String fromPersonUuid,
  required String toPersonUuid,
  required double amount,
}) {
  final key = '$fromPersonUuid->$toPersonUuid';
  final reverseKey = '$toPersonUuid->$fromPersonUuid';
  final reverseAmount = settlementMap[reverseKey] ?? 0;

  if (reverseAmount >= amount) {
    final nextReverseAmount = reverseAmount - amount;
    if (nextReverseAmount <= 0.004) {
      settlementMap.remove(reverseKey);
    } else {
      settlementMap[reverseKey] = nextReverseAmount;
    }
    return;
  }

  settlementMap.remove(reverseKey);
  settlementMap[key] = (settlementMap[key] ?? 0) + amount - reverseAmount;
}
