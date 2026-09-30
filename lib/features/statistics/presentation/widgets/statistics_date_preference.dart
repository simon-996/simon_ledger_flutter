import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/transaction_date.dart';

class StatisticsDatePreference {
  const StatisticsDatePreference({
    required this.month,
    required this.mode,
    this.custom,
  });
  final DateTime month;
  final String mode;
  final TransactionDateRange? custom;

  static Future<StatisticsDatePreference?> read(String ledgerUuid) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('statistics.date.$ledgerUuid');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return StatisticsDatePreference(
        month: DateTime.parse(data['month'] as String),
        mode: data['mode'] as String,
        custom: data['start'] == null || data['end'] == null
            ? null
            : TransactionDateRange.custom(
                DateTime.parse(data['start'] as String),
                DateTime.parse(data['end'] as String),
              ),
      );
    } catch (_) {
      // Older or invalid preferences fall back to the current month.
      return null;
    }
  }

  Future<void> write(String ledgerUuid) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'statistics.date.$ledgerUuid',
      jsonEncode({
        'month': month.toIso8601String(),
        'mode': mode,
        'start': custom?.start.toIso8601String(),
        'end': custom?.end.toIso8601String(),
      }),
    );
  }
}
