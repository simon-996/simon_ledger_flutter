import 'package:shared_preferences/shared_preferences.dart';

class AuthWelcomePreference {
  const AuthWelcomePreference._();

  static const keyPrefix = 'auth_welcome_prompt.shown.v1';

  static Future<bool> hasShown(String? accountUuid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(accountUuid)) ?? false;
  }

  static Future<void> markShown(String? accountUuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(accountUuid), true);
  }

  static String _key(String? accountUuid) {
    final normalized = accountUuid?.trim();
    return normalized == null || normalized.isEmpty
        ? '$keyPrefix.global'
        : '$keyPrefix.$normalized';
  }
}
