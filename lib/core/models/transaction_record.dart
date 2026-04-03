import 'package:isar/isar.dart';

part 'transaction_record.g.dart';

@collection
class TransactionRecord {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  @Index()
  late String ledgerUuid;

  // Type: 0 for expense (支出), 1 for income (收入)
  short type = 0;

  late double amount;
  
  late String currencyCode;
  
  late String category;
  
  List<String> personUuids = [];
  
  late String note;
  
  @Index()
  late DateTime createdAt;
}