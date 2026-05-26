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
  Future<List<Ledger>> getAllLedgers({bool includeDeleted = false}) async {
    final ledgers = await _apiClient.get<List<Ledger>>(
      '/api/ledgers',
      fromJson: (json) =>
          (json! as List<dynamic>).map(_ledgerFromJson).toList(),
    );
    if (ledgers.isEmpty) {
      return ledgers;
    }

    try {
      final peopleByLedger = await _apiClient.get<Map<String, List<String>>>(
        '/api/ledgers/people',
        queryParameters: {
          'ledgerUuids': ledgers.map((ledger) => ledger.uuid).join(','),
        },
        fromJson: _peopleByLedgerFromJson,
      );
      for (final ledger in ledgers) {
        ledger.personUuids = peopleByLedger[ledger.uuid] ?? const [];
      }
    } catch (_) {
      for (final ledger in ledgers) {
        ledger.personUuids = const [];
      }
    }
    return ledgers;
  }

  @override
  Future<void> saveLedger(Ledger ledger) async {
    final data = {
      'name': ledger.name,
      'baseCurrencyCode': ledger.baseCurrencyCode,
      'exchangeRateToCny': ledger.exchangeRateToCNY,
    };

    if (!_looksLikeRemoteUuid(ledger.uuid)) {
      final saved = await _apiClient.post<Ledger>(
        '/api/ledgers',
        data: data,
        idempotencyKey: ledger.uuid,
        fromJson: _ledgerFromJson,
      );
      ledger
        ..uuid = saved.uuid
        ..name = saved.name
        ..baseCurrencyCode = saved.baseCurrencyCode
        ..exchangeRateToCNY = saved.exchangeRateToCNY;
      return;
    }

    await _apiClient.put<Ledger>(
      '/api/ledgers/${ledger.uuid}',
      data: data,
      idempotencyKey: _operationKey('update-ledger', ledger.uuid),
      fromJson: _ledgerFromJson,
    );
  }

  bool _looksLikeRemoteUuid(String uuid) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid);
  }

  String _operationKey(String prefix, String uuid) {
    return '$prefix-$uuid-${DateTime.now().microsecondsSinceEpoch}';
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
          (map['exchangeRateToCny'] as num?)?.toDouble() ?? 1.0
      ..role = map['role']?.toString();
  }

  static Map<String, List<String>> _peopleByLedgerFromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return map.map((ledgerUuid, peopleJson) {
      final personUuids = (peopleJson as List<dynamic>)
          .map((person) => (person as Map<String, dynamic>)['uuid'].toString())
          .toList();
      return MapEntry(ledgerUuid, personUuids);
    });
  }
}
