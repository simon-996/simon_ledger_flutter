import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/preferences/onboarding_preference.dart';

void main() {
  test('onboarding preference stores completion state', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await OnboardingPreference.isCompleted(), isFalse);

    await OnboardingPreference.markCompleted();

    expect(await OnboardingPreference.isCompleted(), isTrue);
  });
}
