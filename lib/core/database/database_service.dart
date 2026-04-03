import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ledger.dart';
import '../models/person.dart';
import '../models/transaction_record.dart';

class DatabaseService {
  late Isar isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open(
      [PersonSchema, LedgerSchema, TransactionRecordSchema],
      directory: dir.path,
    );

    // Initialize default person if empty
    final count = await isar.persons.count();
    if (count == 0) {
      final defaultPerson = Person()
        ..uuid = 'p1'
        ..name = '自己'
        ..avatar = '😎';
      
      await isar.writeTxn(() async {
        await isar.persons.put(defaultPerson);
      });
    }
  }

  // Person operations
  Future<List<Person>> getAllPeople({bool includeDeleted = false}) async {
    if (includeDeleted) {
      return await isar.persons.where().findAll();
    }
    return await isar.persons.filter().isDeletedEqualTo(false).findAll();
  }

  Future<void> savePerson(Person person) async {
    await isar.writeTxn(() async {
      await isar.persons.put(person);
    });
  }

  Future<void> deletePerson(String uuid) async {
    await isar.writeTxn(() async {
      final person = await isar.persons.where().uuidEqualTo(uuid).findFirst();
      if (person != null) {
        person.isDeleted = true;
        await isar.persons.put(person);
      }
    });
  }

  // Ledger operations
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    if (includeDeleted) {
      return await isar.ledgers.where().sortBySortOrder().findAll();
    }
    return await isar.ledgers.filter().isDeletedEqualTo(false).sortBySortOrder().findAll();
  }

  Future<void> saveLedger(Ledger ledger) async {
    await isar.writeTxn(() async {
      await isar.ledgers.put(ledger);
    });
  }

  Future<void> deleteLedger(String uuid) async {
    await isar.writeTxn(() async {
      final ledger = await isar.ledgers.where().uuidEqualTo(uuid).findFirst();
      if (ledger != null) {
        ledger.isDeleted = true;
        await isar.ledgers.put(ledger);
      }
    });
  }

  // Transaction operations
  Future<List<TransactionRecord>> getTransactionsForLedger(String ledgerUuid) async {
    return await isar.transactionRecords
        .where()
        .ledgerUuidEqualTo(ledgerUuid)
        .sortByCreatedAtDesc()
        .findAll();
  }

  Future<void> saveTransaction(TransactionRecord transaction) async {
    await isar.writeTxn(() async {
      await isar.transactionRecords.put(transaction);
    });
  }

  Future<void> deleteTransaction(String uuid) async {
    await isar.writeTxn(() async {
      await isar.transactionRecords.filter().uuidEqualTo(uuid).deleteAll();
    });
  }
}

// Global instance for simple access (will be replaced by Riverpod later as per rules)
final dbService = DatabaseService();