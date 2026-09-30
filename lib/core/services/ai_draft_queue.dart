import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_data_scope.dart';
import '../models/ai_draft.dart';
import '../models/transaction_record.dart';

typedef LoadLedgerTransactions = Future<List<TransactionRecord>> Function(String ledgerUuid);

class AiDraftItem {
  const AiDraftItem({
    required this.uuid,
    required this.operationId,
    required this.draft,
  });

  final String uuid;
  final String operationId;
  final AiDraft draft;

  factory AiDraftItem.fromJson(Map<String, dynamic> json) => AiDraftItem(
    uuid: json['uuid'] as String,
    operationId: json['operationId'] as String,
    draft: AiDraft.fromJson(json['draft'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'operationId': operationId,
    'draft': draft.toJson(),
  };
}

class AiDraftQueue {
  AiDraftQueue({required this.scope, required this.loadTransactions});

  final LocalDataScope scope;
  final LoadLedgerTransactions loadTransactions;

  String _key(String ledgerUuid) =>
      'ai_draft_queue.v1.${scope.storageKey}.$ledgerUuid';

  String _inputKey(String ledgerUuid) =>
      'ai_draft_input.v1.${scope.storageKey}.$ledgerUuid';

  Future<String> readInput(String ledgerUuid) async {
    if (scope.isGuest) return '';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_inputKey(ledgerUuid)) ?? '';
  }

  Future<void> writeInput(String ledgerUuid, String text) async {
    if (scope.isGuest) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inputKey(ledgerUuid), text);
  }

  Future<bool> isSaved(String ledgerUuid, AiDraftItem item) async {
    final transactions = await loadTransactions(ledgerUuid);
    return transactions.any((transaction) =>
      transaction.uuid == item.uuid ||
      transaction.clientOperationId == item.operationId);
  }

  Future<List<AiDraftItem>> load(String ledgerUuid) async {
    if (scope.isGuest) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(ledgerUuid));
    if (raw == null) return [];
    final List<AiDraftItem> items;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1) return [];
      items = (json['items'] as List<dynamic>)
          .map((value) => AiDraftItem.fromJson(value as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
    final saved = await loadTransactions(ledgerUuid);
    final pending = items.where((item) => !saved.any((transaction) =>
      transaction.uuid == item.uuid ||
      transaction.clientOperationId == item.operationId,
    )).toList();
    if (pending.length != items.length) {
      await _write(ledgerUuid, pending);
    }
    return pending;
  }

  Future<List<AiDraftItem>> add(String ledgerUuid, List<AiDraft> drafts) async {
    if (scope.isGuest) throw StateError('AI drafts require an account scope');
    final items = await load(ledgerUuid);
    for (final draft in drafts) {
      final id = _newId();
      items.add(AiDraftItem(uuid: id, operationId: id, draft: draft));
    }
    await _write(ledgerUuid, items);
    return items;
  }

  Future<void> remove(String ledgerUuid, String uuid) async {
    final items = await load(ledgerUuid);
    items.removeWhere((item) => item.uuid == uuid);
    await _write(ledgerUuid, items);
  }

  Future<void> _write(String ledgerUuid, List<AiDraftItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(ledgerUuid), jsonEncode({
      'version': 1,
      'items': items.map((item) => item.toJson()).toList(),
    }));
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
