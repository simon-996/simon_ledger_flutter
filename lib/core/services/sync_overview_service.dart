import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_service.dart';

enum SyncFailureType { ledger, person, transaction }

class SyncFailureItem {
  const SyncFailureItem({
    required this.type,
    required this.title,
    required this.errorText,
  });

  final SyncFailureType type;
  final String title;
  final String errorText;
}

class SyncOverview {
  const SyncOverview({
    required this.ledgerPendingCount,
    required this.personPendingCount,
    required this.transactionPendingCount,
    required this.failedCount,
    required this.localOnlyLedgerCount,
    List<SyncFailureItem>? failures,
    this.lastSuccessfulSyncAt,
  }) : _failures = failures;

  final int ledgerPendingCount;
  final int personPendingCount;
  final int transactionPendingCount;
  final int failedCount;
  final int localOnlyLedgerCount;
  final List<SyncFailureItem>? _failures;
  final DateTime? lastSuccessfulSyncAt;

  List<SyncFailureItem> get failures => _failures ?? const [];

  int get pendingCount =>
      ledgerPendingCount + personPendingCount + transactionPendingCount;
}

class SyncOverviewService {
  const SyncOverviewService(this._database);

  static const _lastSuccessfulSyncAtKey = 'sync.last_successful_at.v1';

  final DatabaseService _database;

  Future<SyncOverview> read() async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    final people = await _database.getAllPeople(includeDeleted: true);
    final transactions = await _database.getTransactionsForLedgers(
      ledgers.map((ledger) => ledger.uuid).toList(),
      includeDeleted: true,
    );
    final syncableLedgerUuids = {
      for (final ledger in ledgers)
        if (ledger.shouldUploadToCloud || ledger.isCloudManaged) ledger.uuid,
    };
    final pendingLedgers = ledgers.where((ledger) {
      return syncableLedgerUuids.contains(ledger.uuid) &&
          (ledger.pendingSync || ledger.shouldUploadToCloud);
    }).toList();
    final pendingPeople = people.where((person) {
      return person.pendingSync &&
          syncableLedgerUuids.contains(person.pendingLedgerUuid);
    }).toList();
    final pendingTransactions = transactions
        .where(
          (transaction) =>
              transaction.pendingSync &&
              syncableLedgerUuids.contains(transaction.ledgerUuid),
        )
        .toList();
    final prefs = await SharedPreferences.getInstance();
    final failures = [
      for (final ledger in pendingLedgers)
        if (_hasError(ledger.syncError))
          SyncFailureItem(
            type: SyncFailureType.ledger,
            title: '账本 · ${ledger.name}',
            errorText: ledger.syncError!,
          ),
      for (final person in pendingPeople)
        if (_hasError(person.syncError))
          SyncFailureItem(
            type: SyncFailureType.person,
            title: '人员 · ${person.name}',
            errorText: person.syncError!,
          ),
      for (final transaction in pendingTransactions)
        if (_hasError(transaction.syncError))
          SyncFailureItem(
            type: SyncFailureType.transaction,
            title: '流水 · ${transaction.category}',
            errorText: transaction.syncError!,
          ),
    ];

    return SyncOverview(
      ledgerPendingCount: pendingLedgers.length,
      personPendingCount: pendingPeople.length,
      transactionPendingCount: pendingTransactions.length,
      localOnlyLedgerCount: ledgers
          .where((ledger) => ledger.isLocalOnly)
          .length,
      failedCount: failures.length,
      failures: failures,
      lastSuccessfulSyncAt: DateTime.tryParse(
        prefs.getString(_lastSuccessfulSyncAtKey) ?? '',
      ),
    );
  }

  Future<void> markSuccessfulSync(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastSuccessfulSyncAtKey,
      timestamp.toIso8601String(),
    );
  }

  bool _hasError(String? error) => error != null && error.isNotEmpty;
}
