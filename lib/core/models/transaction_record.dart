class TransactionRecord {
  int id = 0;

  late String uuid;

  late String ledgerUuid;

  // Type: 0 for expense (支出), 1 for income (收入)
  int type = 0;

  // Null means the transaction uses the shared ledger pool. For expense only,
  // a non-null value means this person paid for the selected participants.
  String? payerPersonUuid;

  String? clientOperationId;

  int? version;

  late double amount;

  late String currencyCode;

  late String category;

  List<String> personUuids = [];

  late String note;

  late DateTime createdAt;

  bool pendingSync = false;

  String? syncError;

  bool isDeleted = false;
}
