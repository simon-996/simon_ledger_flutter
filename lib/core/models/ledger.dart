class Ledger {
  int id = 0;

  late String uuid;

  late String name;

  late String baseCurrencyCode;

  // Rate to convert baseCurrency to CNY (e.g. if USD, rate might be 7.2)
  double exchangeRateToCNY = 1.0;

  // Storing UUIDs of people associated with this ledger
  List<String> personUuids = [];

  int sortOrder = 0;

  bool isDeleted = false; // Soft delete flag

  String? role;

  String get displayCode => 'Simon-$uuid';

  String get displayNameWithCode => '$name · $displayCode';
}
