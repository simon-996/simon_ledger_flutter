import '../repositories/ledger_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/transaction_repository.dart';

class SyncCoordinator {
  const SyncCoordinator({
    required LedgerRepository ledgerRepository,
    required PersonRepository personRepository,
    required TransactionRepository transactionRepository,
  }) : _ledgerRepository = ledgerRepository,
       _personRepository = personRepository,
       _transactionRepository = transactionRepository;

  final LedgerRepository _ledgerRepository;
  final PersonRepository _personRepository;
  final TransactionRepository _transactionRepository;

  Future<TransactionSyncResult> syncLedger(String ledgerUuid) async {
    await _ledgerRepository.syncPendingWrites();
    await _personRepository.syncPendingPeople(ledgerUuid);
    return _transactionRepository.syncPendingTransactions(ledgerUuid);
  }
}
