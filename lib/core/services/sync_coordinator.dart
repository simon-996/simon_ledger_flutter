import '../database/database_service.dart';
import '../repositories/ledger_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/transaction_repository.dart';

class SyncCoordinator {
  const SyncCoordinator({
    required LedgerRepository ledgerRepository,
    required PersonRepository personRepository,
    required TransactionRepository transactionRepository,
    required DatabaseService database,
  }) : _ledgerRepository = ledgerRepository,
       _personRepository = personRepository,
       _transactionRepository = transactionRepository,
       _database = database;

  final LedgerRepository _ledgerRepository;
  final PersonRepository _personRepository;
  final TransactionRepository _transactionRepository;
  final DatabaseService _database;

  Future<TransactionSyncResult> syncLedger(String ledgerUuid) async {
    await _ledgerRepository.syncPendingWrites();
    await _personRepository.syncPendingPeople(ledgerUuid);
    return _transactionRepository.syncPendingTransactions(ledgerUuid);
  }

  Future<bool> syncAllPending() async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    final people = await _database.getAllPeople(includeDeleted: true);
    final transactions = await _database.getTransactionsForLedgers(
      ledgers.map((ledger) => ledger.uuid).toList(),
      includeDeleted: true,
    );
    final ledgerUuids = <String>{
      for (final ledger in ledgers)
        if (ledger.pendingSync || ledger.isLocalTemporary) ledger.uuid,
      for (final person in people)
        if (person.pendingSync && person.pendingLedgerUuid != null)
          person.pendingLedgerUuid!,
      for (final transaction in transactions)
        if (transaction.pendingSync) transaction.ledgerUuid,
    };
    if (ledgerUuids.isEmpty) return false;

    await _ledgerRepository.syncPendingWrites();
    for (final ledgerUuid in ledgerUuids) {
      await _personRepository.syncPendingPeople(ledgerUuid);
      await _transactionRepository.syncPendingTransactions(ledgerUuid);
    }
    return true;
  }
}
