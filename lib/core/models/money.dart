import 'ledger.dart';
import 'transaction_record.dart';

List<String> supportedCurrenciesForLedger(Ledger ledger) {
  final base = ledger.baseCurrencyCode.trim().toUpperCase();
  if (base.isEmpty || base == 'CNY') {
    return const ['CNY'];
  }
  return ['CNY', base];
}

double transactionAmountInCny(TransactionRecord transaction, Ledger ledger) {
  final currency = transaction.currencyCode.trim().toUpperCase();
  if (currency == 'CNY') {
    return transaction.amount;
  }
  if (currency == ledger.baseCurrencyCode.trim().toUpperCase()) {
    return transaction.amount * ledger.exchangeRateToCNY;
  }
  return transaction.amount;
}

double cnyToDisplayAmount(
  double amountInCny,
  String displayCurrency,
  Ledger ledger,
) {
  final currency = displayCurrency.trim().toUpperCase();
  if (currency == 'CNY') {
    return amountInCny;
  }
  final rate = ledger.exchangeRateToCNY;
  if (rate <= 0) {
    return amountInCny;
  }
  return amountInCny / rate;
}

double transactionAmountForDisplay(
  TransactionRecord transaction,
  Ledger ledger,
  String displayCurrency,
) {
  return cnyToDisplayAmount(
    transactionAmountInCny(transaction, ledger),
    displayCurrency,
    ledger,
  );
}

String formatMoney(String currencyCode, double amount, {bool signed = false}) {
  final prefix = signed && amount > 0 ? '+' : '';
  return '$prefix${currencyCode.trim().toUpperCase()} ${amount.toStringAsFixed(2)}';
}

String formatTransactionPrimaryAmount(TransactionRecord transaction) {
  final sign = transaction.type == 0 ? '-' : '+';
  return '$sign ${formatMoney(transaction.currencyCode, transaction.amount)}';
}

String? formatTransactionConvertedAmount(
  TransactionRecord transaction,
  Ledger ledger,
) {
  if (transaction.currencyCode.trim().toUpperCase() == 'CNY') {
    return null;
  }
  final amountInCny = transactionAmountInCny(transaction, ledger);
  return '≈ ${formatMoney('CNY', amountInCny)}';
}
