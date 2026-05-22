class TransactionRecord {
  int id = 0;

  late String uuid;

  late String ledgerUuid;

  // Type: 0 for expense (支出), 1 for income (收入)
  int type = 0;

  late double amount;

  late String currencyCode;

  late String category;

  List<String> personUuids = [];

  late String note;

  late DateTime createdAt;

  bool isDeleted = false;
}
