import 'package:shared_preferences/shared_preferences.dart';

class AuthToken {
  const AuthToken({required this.name, required this.value});

  final String name;
  final String value;

  bool get isValid => name.isNotEmpty && value.isNotEmpty;
}

class TokenStore {
  static const _tokenNameKey = 'auth_token_name';
  static const _tokenValueKey = 'auth_token_value';

  Future<AuthToken?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_tokenNameKey);
    final value = prefs.getString(_tokenValueKey);
    if (name == null || value == null || name.isEmpty || value.isEmpty) {
      return null;
    }
    return AuthToken(name: name, value: value);
  }

  Future<void> save(AuthToken token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenNameKey, token.name);
    await prefs.setString(_tokenValueKey, token.value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenNameKey);
    await prefs.remove(_tokenValueKey);
  }
}
