import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_data_scope.dart';
import '../models/ai_draft.dart';
import '../models/transaction_record.dart';

typedef LoadLedgerTransactions =
    Future<List<TransactionRecord>> Function(String ledgerUuid);

class AiDraftItem {
  const AiDraftItem({
    required this.uuid,
    required this.operationId,
    required this.draft,
    required this.position,
    required this.total,
    this.amountInput,
  });

  final String uuid;
  final String operationId;
  final AiDraft draft;
  final int position;
  final int total;
  final String? amountInput;

  factory AiDraftItem.fromJson(
    Map<String, dynamic> json, {
    required int fallbackPosition,
    required int fallbackTotal,
  }) => AiDraftItem(
    uuid: json['uuid'] as String,
    operationId: json['operationId'] as String,
    draft: AiDraft.fromJson(json['draft'] as Map<String, dynamic>),
    position: json['position'] as int? ?? fallbackPosition,
    total: json['total'] as int? ?? fallbackTotal,
    amountInput: json['amountInput'] as String?,
  );

  AiDraftItem withDraft(AiDraft value, {String? amountInput}) => AiDraftItem(
    uuid: uuid,
    operationId: operationId,
    draft: value,
    position: position,
    total: total,
    amountInput: amountInput ?? this.amountInput,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'operationId': operationId,
    'draft': draft.toJson(),
    'position': position,
    'total': total,
    'amountInput': amountInput,
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
    return transactions.any(
      (transaction) =>
          transaction.uuid == item.uuid ||
          transaction.clientOperationId == item.operationId,
    );
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
      final rawItems = json['items'] as List<dynamic>;
      items = [
        for (var index = 0; index < rawItems.length; index++)
          AiDraftItem.fromJson(
            rawItems[index] as Map<String, dynamic>,
            fallbackPosition: index + 1,
            fallbackTotal: rawItems.length,
          ),
      ];
    } catch (_) {
      return [];
    }
    final saved = await loadTransactions(ledgerUuid);
    final pending = items
        .where(
          (item) => !saved.any(
            (transaction) =>
                transaction.uuid == item.uuid ||
                transaction.clientOperationId == item.operationId,
          ),
        )
        .toList();
    if (pending.length != items.length) {
      await _write(ledgerUuid, pending);
    }
    return pending;
  }

  Future<List<AiDraftItem>> add(String ledgerUuid, List<AiDraft> drafts) async {
    if (scope.isGuest) throw StateError('AI drafts require an account scope');
    final items = await load(ledgerUuid);
    for (var index = 0; index < drafts.length; index++) {
      final id = _newId();
      items.add(
        AiDraftItem(
          uuid: id,
          operationId: id,
          draft: drafts[index],
          position: index + 1,
          total: drafts.length,
        ),
      );
    }
    await _write(ledgerUuid, items);
    return items;
  }

  Future<void> update(
    String ledgerUuid,
    String uuid,
    AiDraft draft, {
    String? amountInput,
  }) async {
    final items = await load(ledgerUuid);
    final index = items.indexWhere((item) => item.uuid == uuid);
    if (index < 0) throw StateError('AI draft no longer exists');
    items[index] = items[index].withDraft(draft, amountInput: amountInput);
    await _write(ledgerUuid, items);
  }

  Future<void> remove(String ledgerUuid, String uuid) async {
    final items = await load(ledgerUuid);
    items.removeWhere((item) => item.uuid == uuid);
    await _write(ledgerUuid, items);
  }

  Future<void> _write(String ledgerUuid, List<AiDraftItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(ledgerUuid),
      jsonEncode({
        'version': 1,
        'items': items.map((item) => item.toJson()).toList(),
      }),
    );
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
