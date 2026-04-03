import 'package:isar/isar.dart';

part 'ledger.g.dart';

@collection
class Ledger {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  late String name;
  
  late String baseCurrencyCode;
  
  // Rate to convert baseCurrency to CNY (e.g. if USD, rate might be 7.2)
  double exchangeRateToCNY = 1.0;

  // Storing UUIDs of people associated with this ledger
  List<String> personUuids = [];
  
  int sortOrder = 0;

  bool isDeleted = false; // Soft delete flag
}