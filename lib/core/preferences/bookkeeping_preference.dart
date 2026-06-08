import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BookkeepingDraftPreference {
  const BookkeepingDraftPreference._();

  static const _key = 'bookkeeping_draft.v1';

  static Future<BookkeepingDraft?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return BookkeepingDraft.fromJson(decoded);
  }

  static Future<void> write(BookkeepingDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }
}

class BookkeepingDraft {
  const BookkeepingDraft({
    required this.ledgerUuid,
    required this.transactionType,
    required this.category,
    required this.currencyCode,
    required this.personUuids,
    this.payerPersonUuid,
  });

  final String ledgerUuid;
  final int transactionType;
  final String category;
  final String currencyCode;
  final List<String> personUuids;
  final String? payerPersonUuid;

  factory BookkeepingDraft.fromJson(Map<String, dynamic> json) {
    return BookkeepingDraft(
      ledgerUuid: json['ledgerUuid']?.toString() ?? '',
      transactionType: (json['transactionType'] as num?)?.toInt() ?? 0,
      category: json['category']?.toString() ?? '默认',
      currencyCode: json['currencyCode']?.toString() ?? 'CNY',
      personUuids: (json['personUuids'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
      payerPersonUuid: json['payerPersonUuid']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ledgerUuid': ledgerUuid,
      'transactionType': transactionType,
      'category': category,
      'currencyCode': currencyCode,
      'personUuids': personUuids,
      'payerPersonUuid': payerPersonUuid,
    };
  }
}
