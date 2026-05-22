import '../database/database_service.dart';
import '../models/ledger.dart';
import '../network/api_client.dart';

abstract class LedgerRepository {
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false});

  Future<void> saveLedger(Ledger ledger);

  Future<void> deleteLedger(String uuid);
}

class LocalLedgerRepository implements LedgerRepository {
  const LocalLedgerRepository(this._db);

  final DatabaseService _db;

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) {
    return _db.getAllLedgers(includeDeleted: includeDeleted);
  }

  @override
  Future<void> saveLedger(Ledger ledger) {
    return _db.saveLedger(ledger);
  }

  @override
  Future<void> deleteLedger(String uuid) {
    return _db.deleteLedger(uuid);
  }
}

class RemoteLedgerRepository implements LedgerRepository {
  const RemoteLedgerRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) {
    return _apiClient.get<List<Ledger>>(
      '/api/ledgers',
      fromJson: (json) =>
          (json! as List<dynamic>).map(_ledgerFromJson).toList(),
    );
  }

  @override
  Future<void> saveLedger(Ledger ledger) async {
    final data = {
      'name': ledger.name,
      'baseCurrencyCode': ledger.baseCurrencyCode,
      'exchangeRateToCny': ledger.exchangeRateToCNY,
    };

    if (ledger.uuid.isEmpty) {
      await _apiClient.post<Ledger>(
        '/api/ledgers',
        data: data,
        idempotencyKey: DateTime.now().microsecondsSinceEpoch.toString(),
        fromJson: _ledgerFromJson,
      );
      return;
    }

    try {
      await _apiClient.put<Ledger>(
        '/api/ledgers/${ledger.uuid}',
        data: data,
        idempotencyKey: DateTime.now().microsecondsSinceEpoch.toString(),
        fromJson: _ledgerFromJson,
      );
    } catch (_) {
      await _apiClient.post<Ledger>(
        '/api/ledgers',
        data: data,
        idempotencyKey: ledger.uuid,
        fromJson: _ledgerFromJson,
      );
    }
  }

  @override
  Future<void> deleteLedger(String uuid) {
    return _apiClient.deleteVoid(
      '/api/ledgers/$uuid',
      idempotencyKey: 'delete-ledger-$uuid',
    );
  }

  static Ledger _ledgerFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return Ledger()
      ..uuid = map['uuid'].toString()
      ..name = map['name'].toString()
      ..baseCurrencyCode = map['baseCurrencyCode'].toString()
      ..exchangeRateToCNY =
          (map['exchangeRateToCny'] as num?)?.toDouble() ?? 1.0;
  }
}
