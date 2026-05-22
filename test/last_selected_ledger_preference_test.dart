import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/preferences/last_selected_ledger_preference.dart';

void main() {
  group('LastSelectedLedgerPreference', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('stores and reads the last selected ledger uuid', () async {
      await LastSelectedLedgerPreference.setUuid('ledger-a');

      expect(await LastSelectedLedgerPreference.getUuid(), 'ledger-a');
    });

    test('clears only when the uuid matches', () async {
      await LastSelectedLedgerPreference.setUuid('ledger-a');

      await LastSelectedLedgerPreference.clearIfMatches('ledger-b');
      expect(await LastSelectedLedgerPreference.getUuid(), 'ledger-a');

      await LastSelectedLedgerPreference.clearIfMatches('ledger-a');
      expect(await LastSelectedLedgerPreference.getUuid(), isNull);
    });
  });
}
