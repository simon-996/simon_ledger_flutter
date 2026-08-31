import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/services/sync_overview_service.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';

void main() {
  test('SyncOverview treats a missing failure list as empty', () {
    const overview = SyncOverview(
      ledgerPendingCount: 0,
      personPendingCount: 0,
      transactionPendingCount: 0,
      failedCount: 0,
      localOnlyLedgerCount: 0,
      failures: null,
    );

    expect(overview.failures, isEmpty);
  });

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

  test(
    'SyncOverview reports conflicts separately from pending failures',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      final conflicts = ConflictStore();
      final tokenStore = TokenStore();
      await tokenStore.saveAccountUuid('account-a');
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-1'
          ..name = '共享账本'
          ..baseCurrencyCode = 'CNY'
          ..cloudPolicy = LedgerCloudPolicy.cloudManaged,
      );
      await database.saveTransaction(
        TransactionRecord()
          ..uuid = 'pending-transaction'
          ..ledgerUuid = 'ledger-1'
          ..amount = 20
          ..currencyCode = 'CNY'
          ..category = '餐饮'
          ..note = ''
          ..createdAt = DateTime(2026, 8, 30)
          ..pendingSync = true,
      );
      await conflicts.upsert(_conflict('transaction-1', 'ledger-1'));
      await conflicts.upsert(
        _conflict('profile-1', null, entityType: ConflictEntityType.profile),
      );
      await conflicts.upsert(
        _conflict(
          'account-b-transaction',
          'ledger-1',
          accountUuid: 'account-b',
        ),
      );

      final overview = await SyncOverviewService(
        database,
        conflictStore: conflicts,
        tokenStore: tokenStore,
      ).read();

      expect(overview.conflictCount, 2);
      expect(overview.conflictsByLedger['ledger-1'], 1);
      expect(overview.pendingCount, 1);
      expect(overview.failedCount, 0);
    },
  );
}

ConflictRecord _conflict(
  String remoteUuid,
  String? ledgerUuid, {
  ConflictEntityType entityType = ConflictEntityType.transaction,
  String accountUuid = 'account-a',
}) {
  return ConflictRecord(
    id: 'conflict-$remoteUuid',
    accountUuid: accountUuid,
    entityType: entityType,
    ledgerUuid: ledgerUuid,
    localUuid: remoteUuid,
    remoteUuid: remoteUuid,
    operation: ConflictOperation.update,
    baseVersion: 1,
    remoteVersion: 2,
    localSnapshot: const {},
    remoteSnapshot: const {},
    remoteDeleted: false,
    detectedAt: DateTime(2026, 8, 30),
  );
}
