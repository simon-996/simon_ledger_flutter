import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/preferences/auth_welcome_preference.dart';

void main() {
  test('auth welcome preference is scoped per account', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await AuthWelcomePreference.hasShown('user-1'), isFalse);
    expect(await AuthWelcomePreference.hasShown('user-2'), isFalse);

    await AuthWelcomePreference.markShown('user-1');

    expect(await AuthWelcomePreference.hasShown('user-1'), isTrue);
    expect(await AuthWelcomePreference.hasShown('user-2'), isFalse);
  });
}
