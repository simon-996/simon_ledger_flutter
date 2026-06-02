import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/services/sync_overview_service.dart';

void main() {
  test('SyncOverviewService summarizes local pending writes', () async {
    SharedPreferences.setMockInitialValues({});
    final database = DatabaseService();
    await database.saveLedger(
      Ledger()
        ..uuid = 'local-ledger'
        ..name = '离线账本'
        ..baseCurrencyCode = 'CNY'
        ..cloudPolicy = LedgerCloudPolicy.uploadRequested,
    );
    await database.savePerson(
      Person()
        ..uuid = 'local-person'
        ..name = '本人'
        ..pendingSync = true
        ..pendingLedgerUuid = 'local-ledger',
    );
    await database.saveTransaction(
      TransactionRecord()
        ..uuid = 'local-transaction'
        ..ledgerUuid = 'local-ledger'
        ..amount = 12
        ..currencyCode = 'CNY'
        ..category = '餐饮'
        ..note = ''
        ..createdAt = DateTime(2026)
        ..pendingSync = true
        ..syncError = 'offline',
    );

    final overview = await SyncOverviewService(database).read();

    expect(overview.ledgerPendingCount, 1);
    expect(overview.personPendingCount, 1);
    expect(overview.transactionPendingCount, 1);
    expect(overview.pendingCount, 3);
    expect(overview.failedCount, 1);
    expect(overview.failures.single.type, SyncFailureType.transaction);
    expect(overview.failures.single.title, '流水 · 餐饮');
    expect(overview.failures.single.errorText, 'offline');
  });

  test('SyncOverviewService stores the last successful sync time', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SyncOverviewService(DatabaseService());
    final timestamp = DateTime.utc(2026, 6, 1, 10, 30);

    await service.markSuccessfulSync(timestamp);
    final overview = await service.read();

    expect(overview.lastSuccessfulSyncAt, timestamp);
  });
}
