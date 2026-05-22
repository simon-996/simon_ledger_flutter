import 'package:shared_preferences/shared_preferences.dart';

class LastSelectedLedgerPreference {
  const LastSelectedLedgerPreference._();

  static const key = 'last_selected_ledger_uuid';

  static Future<String?> getUuid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> setUuid(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, uuid);
  }

  static Future<void> clearIfMatches(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(key) == uuid) {
      await prefs.remove(key);
    }
  }
}
