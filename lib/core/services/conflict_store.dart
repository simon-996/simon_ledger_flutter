import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conflict_record.dart';

class ConflictStore {
  static const storageKey = 'local_store.conflicts.v1';
  static const quarantineKey = 'local_store.conflicts.quarantine.v1';
  Future<void> _tail = Future<void>.value();
  final StreamController<int> _changes = StreamController<int>.broadcast(
    sync: true,
  );
  int _revision = 0;

  Stream<int> watchChanges() async* {
    yield _revision;
    yield* _changes.stream;
  }

  Future<List<ConflictRecord>> readAll({String? accountUuid}) {
    return _exclusive(() async {
      final stored = await _readUnsafe();
      if (accountUuid == null) return stored.records;
      return stored.records
          .where((record) => record.accountUuid == accountUuid)
          .toList();
    });
  }

  Future<ConflictRecord?> findById(
    String id, {
    required String accountUuid,
  }) async {
    final records = await readAll(accountUuid: accountUuid);
    return records.where((record) => record.id == id).firstOrNull;
  }

  Future<ConflictRecord> upsert(ConflictRecord incoming) {
    return _exclusive(() async {
      final stored = await _readUnsafe();
      final records = List<ConflictRecord>.from(stored.records);
      final index = records.indexWhere(
        (record) =>
            record.accountUuid == incoming.accountUuid &&
            record.entityType == incoming.entityType &&
            record.remoteUuid == incoming.remoteUuid,
      );
      final ConflictRecord saved;
      if (index == -1) {
        saved = incoming.copyWith(state: ConflictState.unresolved, error: null);
        records.add(saved);
      } else {
        final current = records[index];
        saved = incoming.copyWith(
          id: current.id,
          detectedAt: current.detectedAt,
          state: ConflictState.unresolved,
          error: null,
        );
        records[index] = saved;
      }
      await _writeUnsafe(records, invalidEntries: stored.invalidEntries);
      return saved;
    });
  }

  Future<ConflictRecord?> updateState(
    String id,
    String accountUuid,
    ConflictState state, {
    String? error,
  }) {
    return _exclusive(() async {
      final stored = await _readUnsafe();
      final records = List<ConflictRecord>.from(stored.records);
      final index = records.indexWhere(
        (record) => record.id == id && record.accountUuid == accountUuid,
      );
      if (index == -1) return null;
      final updated = records[index].copyWith(state: state, error: error);
      records[index] = updated;
      await _writeUnsafe(records, invalidEntries: stored.invalidEntries);
      return updated;
    });
  }

  Future<void> remove(String id, {required String accountUuid}) {
    return _exclusive(() async {
      final stored = await _readUnsafe();
      final records = List<ConflictRecord>.from(stored.records)
        ..removeWhere(
          (record) => record.id == id && record.accountUuid == accountUuid,
        );
      await _writeUnsafe(records, invalidEntries: stored.invalidEntries);
    });
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<_StoredConflicts> _readUnsafe() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const _StoredConflicts();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        await prefs.setString(quarantineKey, raw);
        return const _StoredConflicts();
      }
      final records = <ConflictRecord>[];
      final invalidEntries = <Object?>[];
      for (final value in decoded) {
        try {
          if (value is! Map<dynamic, dynamic>) {
            throw const FormatException('冲突记录格式不正确');
          }
          records.add(ConflictRecord.fromJson(value.cast<String, dynamic>()));
        } on FormatException {
          invalidEntries.add(value);
        } on TypeError {
          invalidEntries.add(value);
        }
      }
      records.sort(
        (left, right) => left.detectedAt.compareTo(right.detectedAt),
      );
      if (invalidEntries.isNotEmpty) {
        await prefs.setString(quarantineKey, jsonEncode(invalidEntries));
      }
      return _StoredConflicts(records: records, invalidEntries: invalidEntries);
    } on FormatException {
      await prefs.setString(quarantineKey, raw);
      return const _StoredConflicts();
    } on TypeError {
      await prefs.setString(quarantineKey, raw);
      return const _StoredConflicts();
    }
  }

  Future<void> _writeUnsafe(
    List<ConflictRecord> records, {
    List<Object?> invalidEntries = const [],
  }) async {
    records.sort((left, right) => left.detectedAt.compareTo(right.detectedAt));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode([
        ...records.map((record) => record.toJson()),
        ...invalidEntries,
      ]),
    );
    _revision += 1;
    _changes.add(_revision);
  }
}

class _StoredConflicts {
  const _StoredConflicts({
    this.records = const [],
    this.invalidEntries = const [],
  });

  final List<ConflictRecord> records;
  final List<Object?> invalidEntries;
}
