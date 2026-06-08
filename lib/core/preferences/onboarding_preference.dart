import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPreference {
  const OnboardingPreference._();

  static const completedKey = 'onboarding.completed.v1';

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(completedKey, true);
  }
}
