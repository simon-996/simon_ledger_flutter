import 'dart:typed_data';

import '../models/ai_draft.dart';
import '../preferences/transaction_category_preference.dart';
import '../network/api_client.dart';

class AiCapability {
  const AiCapability({
    required this.textAvailable,
    required this.voiceAvailable,
    this.reason,
  });

  final bool textAvailable;
  final bool voiceAvailable;
  final String? reason;

  factory AiCapability.fromJson(Map<String, dynamic> json) => AiCapability(
    textAvailable: json['textAvailable'] == true,
    voiceAvailable: json['voiceAvailable'] == true,
    reason: json['reason'] as String?,
  );
}

class AiBookkeepingRepository {
  const AiBookkeepingRepository(this.apiClient);

  final ApiClient apiClient;

  String _path(String ledgerUuid) =>
      '/api/ledgers/${Uri.encodeComponent(ledgerUuid)}/ai-bookkeeping';

  Future<AiCapability> capability(String ledgerUuid) =>
      apiClient.get<AiCapability>(
        '${_path(ledgerUuid)}/capability',
        fromJson: (json) => AiCapability.fromJson(json as Map<String, dynamic>),
      );

  Future<List<AiDraft>> parse(
    String ledgerUuid,
    String text,
    String zone, {
    List<String>? expenseCategories,
    List<String>? incomeCategories,
  }) async {
    final categories = await TransactionCategoryPreference.read();
    return apiClient.post<List<AiDraft>>(
      '${_path(ledgerUuid)}/parse',
      data: {
        'text': text,
        'zone': zone,
        'expenseCategories': expenseCategories ?? categories.expense,
        'incomeCategories': incomeCategories ?? categories.income,
      },
      fromJson: (json) =>
          ((json as Map<String, dynamic>)['entries'] as List<dynamic>)
              .map((entry) => AiDraft.fromJson(entry as Map<String, dynamic>))
              .toList(),
    );
  }

  Future<String> transcribe(String ledgerUuid, Uint8List pcm) =>
      apiClient.postBytes<String>(
        '${_path(ledgerUuid)}/transcribe',
        data: pcm,
        fromJson: (json) => (json as Map<String, dynamic>)['text'] as String,
      );
}
