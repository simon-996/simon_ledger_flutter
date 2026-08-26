import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conflict_record.dart';

class ConflictStore {
  static const storageKey = 'local_store.conflicts.v1';
  static Future<void> _tail = Future<void>.value();

  Future<List<ConflictRecord>> readAll() {
    return _exclusive(_readUnsafe);
  }

  Future<ConflictRecord?> findById(String id) async {
    final records = await readAll();
    return records.where((record) => record.id == id).firstOrNull;
  }

  Future<ConflictRecord> upsert(ConflictRecord incoming) {
    return _exclusive(() async {
      final records = await _readUnsafe();
      final index = records.indexWhere(
        (record) =>
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
      await _writeUnsafe(records);
      return saved;
    });
  }

  Future<ConflictRecord?> updateState(
    String id,
    ConflictState state, {
    String? error,
  }) {
    return _exclusive(() async {
      final records = await _readUnsafe();
      final index = records.indexWhere((record) => record.id == id);
      if (index == -1) return null;
      final updated = records[index].copyWith(state: state, error: error);
      records[index] = updated;
      await _writeUnsafe(records);
      return updated;
    });
  }

  Future<void> remove(String id) {
    return _exclusive(() async {
      final records = await _readUnsafe();
      records.removeWhere((record) => record.id == id);
      await _writeUnsafe(records);
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

  Future<List<ConflictRecord>> _readUnsafe() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return [];
      final records = decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (value) => ConflictRecord.fromJson(value.cast<String, dynamic>()),
          )
          .toList();
      records.sort(
        (left, right) => left.detectedAt.compareTo(right.detectedAt),
      );
      return records;
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> _writeUnsafe(List<ConflictRecord> records) async {
    records.sort((left, right) => left.detectedAt.compareTo(right.detectedAt));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }
}
