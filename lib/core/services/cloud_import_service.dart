import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_service.dart';
import '../models/ledger.dart';
import 'sync_coordinator.dart';

class LocalLedgerImportCandidate {
  const LocalLedgerImportCandidate({
    required this.ledger,
    required this.transactionCount,
    required this.imported,
    this.remoteLedgerUuid,
  });

  final Ledger ledger;
  final int transactionCount;
  final bool imported;
  final String? remoteLedgerUuid;
}

class CloudImportProgress {
  const CloudImportProgress({
    required this.message,
    required this.done,
    required this.total,
  });

  final String message;
  final int done;
  final int total;
}

class CloudImportService {
  const CloudImportService({
    required DatabaseService database,
    required SyncCoordinator syncCoordinator,
  }) : _database = database,
       _syncCoordinator = syncCoordinator;

  final DatabaseService _database;
  final SyncCoordinator _syncCoordinator;

  Future<List<LocalLedgerImportCandidate>> scanLocalLedgers() async {
    final ledgers = await _database.getAllLedgers();
    final candidates = <LocalLedgerImportCandidate>[];

    for (final ledger in ledgers.where((ledger) => ledger.isLocalTemporary)) {
      await _migrateLegacyImportMapping(ledger);
      final transactions = await _database.getTransactionsForLedger(
        ledger.uuid,
      );
      candidates.add(
        LocalLedgerImportCandidate(
          ledger: ledger,
          transactionCount: transactions.length,
          imported: ledger.hasSyncedRemoteCopy,
          remoteLedgerUuid: ledger.syncedRemoteUuid,
        ),
      );
    }

    return candidates;
  }

  Future<void> importLedgers(
    List<String> ledgerUuids, {
    void Function(CloudImportProgress progress)? onProgress,
  }) async {
    final selectedUuidSet = ledgerUuids.toSet();
    final ledgers = await _database.getAllLedgers();
    final selectedLedgers = ledgers.where((ledger) {
      return selectedUuidSet.contains(ledger.uuid) &&
          ledger.isLocalTemporary &&
          !ledger.hasSyncedRemoteCopy;
    }).toList();

    for (var index = 0; index < selectedLedgers.length; index++) {
      final ledger = selectedLedgers[index];
      final step = index + 1;
      onProgress?.call(
        CloudImportProgress(
          message: '正在同步 ${ledger.displayNameWithCode}',
          done: index,
          total: selectedLedgers.length,
        ),
      );

      await _database.saveLedger(
        ledger
          ..cloudPolicy = LedgerCloudPolicy.uploadRequested
          ..pendingSync = true
          ..syncError = null,
      );
      final result = await _syncCoordinator.syncLedger(
        ledger.uuid,
        force: true,
      );
      if (result.error != null) {
        throw result.error!;
      }
      final syncedLedger = await _findLedger(ledger.uuid);
      if (syncedLedger == null || !syncedLedger.hasSyncedRemoteCopy) {
        throw StateError('账本暂时未能同步，请检查网络后重试。');
      }

      onProgress?.call(
        CloudImportProgress(
          message: '${ledger.displayNameWithCode} 同步完成',
          done: step,
          total: selectedLedgers.length,
        ),
      );
    }
  }

  Future<void> _migrateLegacyImportMapping(Ledger ledger) async {
    if (ledger.hasSyncedRemoteCopy) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final remoteUuid = prefs.getString(_legacyImportedLedgerKey(ledger.uuid));
    if (remoteUuid == null || remoteUuid.isEmpty) {
      return;
    }
    ledger
      ..syncedRemoteUuid = remoteUuid
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged;
    await _database.saveLedger(ledger);
  }

  Future<Ledger?> _findLedger(String uuid) async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    return ledgers.where((ledger) => ledger.uuid == uuid).firstOrNull;
  }

  String _legacyImportedLedgerKey(String ledgerUuid) {
    return 'cloud_import.ledger.$ledgerUuid';
  }
}
