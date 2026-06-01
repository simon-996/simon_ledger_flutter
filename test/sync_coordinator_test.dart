import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/repositories/ledger_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/person_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/transaction_repository.dart';
import 'package:simon_ledger_flutter/core/services/sync_coordinator.dart';

void main() {
  test('syncs ledger, people, and transactions in dependency order', () async {
    final calls = <String>[];
    final coordinator = SyncCoordinator(
      ledgerRepository: _LedgerRepository(calls),
      personRepository: _PersonRepository(calls),
      transactionRepository: _TransactionRepository(calls),
    );

    final result = await coordinator.syncLedger('local-ledger');

    expect(calls, ['ledger', 'people:local-ledger', 'tx:local-ledger']);
    expect(result.synced, 1);
  });
}

class _LedgerRepository implements LedgerRepository {
  const _LedgerRepository(this.calls);

  final List<String> calls;

  @override
  Future<void> syncPendingWrites() async => calls.add('ledger');

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async => [];

  @override
  Future<void> saveLedger(Ledger ledger) async {}

  @override
  Future<CreatedLedgerWithPeople> createLedgerWithPeople(
    Ledger ledger,
    List<Person> people,
  ) async {
    return CreatedLedgerWithPeople(ledger: ledger, people: people);
  }

  @override
  Future<void> deleteLedger(String uuid) async {}
}

class _PersonRepository implements PersonRepository {
  const _PersonRepository(this.calls);

  final List<String> calls;

  @override
  Future<void> syncPendingPeople(String ledgerUuid) async {
    calls.add('people:$ledgerUuid');
  }

  @override
  Future<List<Person>> getAllPeople({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) async => [];

  @override
  Future<void> savePerson(Person person, {String? ledgerUuid}) async {}

  @override
  Future<void> deletePerson(String uuid, {String? ledgerUuid}) async {}
}

class _TransactionRepository implements TransactionRepository {
  const _TransactionRepository(this.calls);

  final List<String> calls;

  @override
  Future<TransactionSyncResult> syncPendingTransactions(
    String ledgerUuid,
  ) async {
    calls.add('tx:$ledgerUuid');
    return const TransactionSyncResult(synced: 1);
  }

  @override
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) async => [];

  @override
  Future<List<TransactionRecord>> getTransactionsForLedgers(
    List<String> ledgerUuids, {
    bool includeDeleted = false,
  }) async => [];

  @override
  Future<void> saveTransaction(TransactionRecord transaction) async {}

  @override
  Future<void> deleteTransaction(String ledgerUuid, String uuid) async {}
}
