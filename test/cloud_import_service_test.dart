import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/repositories/ledger_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/person_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/transaction_repository.dart';
import 'package:simon_ledger_flutter/core/services/cloud_import_service.dart';
import 'package:simon_ledger_flutter/core/services/sync_coordinator.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('scan exposes only local ledgers and keeps synced state', () async {
    final database = DatabaseService();
    await database.saveLedger(_ledger('local-pending'));
    await database.saveLedger(
      _ledger('local-synced')..syncedRemoteUuid = _remoteLedgerUuid,
    );
    await database.saveLedger(_ledger(_anotherRemoteLedgerUuid));
    final service = _service(database);

    final candidates = await service.scanLocalLedgers();

    expect(candidates.map((candidate) => candidate.ledger.uuid), [
      'local-pending',
      'local-synced',
    ]);
    expect(candidates.first.imported, isFalse);
    expect(candidates.last.imported, isTrue);
    expect(candidates.last.remoteLedgerUuid, _remoteLedgerUuid);
  });

  test('import syncs only selected local ledger through coordinator', () async {
    final database = DatabaseService();
    await database.saveLedger(_ledger('local-selected'));
    await database.saveLedger(_ledger('local-unselected'));
    final calls = <String>[];
    final service = _service(database, calls: calls);

    await service.importLedgers(['local-selected']);

    expect(calls, [
      'ledger:local-selected',
      'people:local-selected',
      'tx:local-selected',
    ]);
    final ledgers = await database.getAllLedgers();
    expect(
      ledgers
          .firstWhere((ledger) => ledger.uuid == 'local-selected')
          .hasSyncedRemoteCopy,
      isTrue,
    );
    expect(
      ledgers
          .firstWhere((ledger) => ledger.uuid == 'local-unselected')
          .hasSyncedRemoteCopy,
      isFalse,
    );
  });

  test('scan migrates legacy imported ledger mapping', () async {
    SharedPreferences.setMockInitialValues({
      'cloud_import.ledger.local-ledger': _remoteLedgerUuid,
    });
    final database = DatabaseService();
    await database.saveLedger(_ledger('local-ledger'));
    final service = _service(database);

    final candidates = await service.scanLocalLedgers();

    expect(candidates.single.imported, isTrue);
    expect(candidates.single.remoteLedgerUuid, _remoteLedgerUuid);
    expect(
      (await database.getAllLedgers()).single.syncedRemoteUuid,
      _remoteLedgerUuid,
    );
  });
}

CloudImportService _service(DatabaseService database, {List<String>? calls}) {
  final history = calls ?? <String>[];
  return CloudImportService(
    database: database,
    syncCoordinator: SyncCoordinator(
      ledgerRepository: _LedgerRepository(database, history),
      personRepository: _PersonRepository(history),
      transactionRepository: _TransactionRepository(history),
      database: database,
    ),
  );
}

Ledger _ledger(String uuid) {
  return Ledger()
    ..uuid = uuid
    ..name = uuid
    ..baseCurrencyCode = 'CNY';
}

const _remoteLedgerUuid = '1234567890abcdef1234567890abcdef';
const _anotherRemoteLedgerUuid = 'abcdef1234567890abcdef1234567890';

class _LedgerRepository implements LedgerRepository {
  const _LedgerRepository(this.database, this.calls);

  final DatabaseService database;
  final List<String> calls;

  @override
  Future<void> syncPendingWrites({String? ledgerUuid}) async {
    calls.add(ledgerUuid == null ? 'ledger' : 'ledger:$ledgerUuid');
    if (ledgerUuid == null) return;
    final ledgers = await database.getAllLedgers();
    final ledger = ledgers.where((ledger) => ledger.uuid == ledgerUuid).single;
    ledger.syncedRemoteUuid = _remoteLedgerUuid;
    await database.saveLedger(ledger);
  }

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) {
    return database.getAllLedgers(includeDeleted: includeDeleted);
  }

  @override
  Future<List<Ledger>> getCachedLedgers({bool includeDeleted = false}) {
    return database.getAllLedgers(includeDeleted: includeDeleted);
  }

  @override
  Future<void> saveLedger(Ledger ledger) => database.saveLedger(ledger);

  @override
  Future<CreatedLedgerWithPeople> createLedgerWithPeople(
    Ledger ledger,
    List<Person> people,
  ) async {
    return CreatedLedgerWithPeople(ledger: ledger, people: people);
  }

  @override
  Future<void> deleteLedger(String uuid) => database.deleteLedger(uuid);
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
  Future<List<Person>> getCachedPeople({
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
    return const TransactionSyncResult(synced: 0);
  }

  @override
  Future<List<TransactionRecord>> getTransactionsForLedger(
    String ledgerUuid, {
    bool includeDeleted = false,
  }) async => [];

  @override
  Future<List<TransactionRecord>> getCachedTransactionsForLedger(
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
