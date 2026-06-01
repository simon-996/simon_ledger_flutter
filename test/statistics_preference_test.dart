import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/preferences/statistics_preference.dart';

void main() {
  test('StatisticsPreference stores and restores filters', () async {
    SharedPreferences.setMockInitialValues({});

    await StatisticsPreference.write(
      const StatisticsPreference(
        ledgerUuid: 'ledger-1',
        timeFilter: 'year',
        transactionType: 1,
        displayCurrency: 'USD',
      ),
    );

    final restored = await StatisticsPreference.read();

    expect(restored?.ledgerUuid, 'ledger-1');
    expect(restored?.timeFilter, 'year');
    expect(restored?.transactionType, 1);
    expect(restored?.displayCurrency, 'USD');
  });

  test(
    'StatisticsPreference returns null when no filters are stored',
    () async {
      SharedPreferences.setMockInitialValues({});

      expect(await StatisticsPreference.read(), isNull);
    },
  );
}
