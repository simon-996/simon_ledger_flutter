import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_profile.dart';

class LocalProfileStore {
  const LocalProfileStore();

  static const _nicknameKey = 'local_profile.nickname.v1';
  static const _avatarIconKey = 'local_profile.avatar_icon.v1';

  Future<LocalProfile> read() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalProfile(
      nickname:
          prefs.getString(_nicknameKey) ?? LocalProfile.defaultProfile.nickname,
      avatarIcon:
          prefs.getString(_avatarIconKey) ??
          LocalProfile.defaultProfile.avatarIcon,
    );
  }

  Future<void> save(LocalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameKey, profile.normalizedNickname);
    await prefs.setString(_avatarIconKey, profile.avatarIcon);
  }
}
