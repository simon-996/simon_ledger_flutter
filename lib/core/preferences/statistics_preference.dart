import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StatisticsPreference {
  const StatisticsPreference({
    this.ledgerUuid,
    required this.timeFilter,
    required this.transactionType,
    required this.displayCurrency,
  });

  static const _key = 'statistics_preference.v1';

  final String? ledgerUuid;
  final String timeFilter;
  final int transactionType;
  final String displayCurrency;

  static Future<StatisticsPreference?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return StatisticsPreference(
      ledgerUuid: decoded['ledgerUuid']?.toString(),
      timeFilter: decoded['timeFilter']?.toString() ?? 'month',
      transactionType: (decoded['transactionType'] as num?)?.toInt() ?? 0,
      displayCurrency: decoded['displayCurrency']?.toString() ?? 'CNY',
    );
  }

  static Future<void> write(StatisticsPreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'ledgerUuid': preference.ledgerUuid,
        'timeFilter': preference.timeFilter,
        'transactionType': preference.transactionType,
        'displayCurrency': preference.displayCurrency,
      }),
    );
  }
}
