import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/utils/transaction_date.dart';
import 'package:simon_ledger_flutter/features/statistics/presentation/widgets/statistics_date_preference.dart';

void main() {
  test(
    'calendar and custom selections persist only for their ledger',
    () async {
      SharedPreferences.setMockInitialValues({});
      await StatisticsDatePreference(
        month: DateTime(2024, 2),
        mode: 'custom',
        custom: TransactionDateRange.custom(
          DateTime(2024, 2, 3),
          DateTime(2024, 2, 29),
        ),
      ).write('a');
      final saved = await StatisticsDatePreference.read('a');
      expect(saved!.month, DateTime(2024, 2));
      expect(saved.mode, 'custom');
      expect(saved.custom!.contains(DateTime(2024, 2, 29, 23, 59)), isTrue);
      expect(await StatisticsDatePreference.read('b'), isNull);
    },
  );
  test('invalid date preferences gracefully default', () async {
    SharedPreferences.setMockInitialValues({
      'statistics.date.a': '{"month":"invalid"}',
    });
    expect(await StatisticsDatePreference.read('a'), isNull);
  });
}
