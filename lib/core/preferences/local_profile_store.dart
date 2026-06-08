import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_profile.dart';

class LocalProfileStore {
  const LocalProfileStore();

  static const _nicknameKey = 'local_profile.nickname.v1';
  static const _avatarIconKey = 'local_profile.avatar_icon.v1';
  static const _pendingSyncKey = 'local_profile.pending_sync.v1';
  static const _pendingOperationIdKey = 'local_profile.pending_operation_id.v1';
  static const _syncErrorKey = 'local_profile.sync_error.v1';
  static const _updatedAtKey = 'local_profile.updated_at.v1';

  Future<LocalProfile> read() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalProfile(
      nickname:
          prefs.getString(_nicknameKey) ?? LocalProfile.defaultProfile.nickname,
      avatarIcon:
          prefs.getString(_avatarIconKey) ??
          LocalProfile.defaultProfile.avatarIcon,
      pendingSync: prefs.getBool(_pendingSyncKey) ?? false,
      pendingOperationId: prefs.getString(_pendingOperationIdKey),
      syncError: prefs.getString(_syncErrorKey),
      updatedAt: DateTime.tryParse(prefs.getString(_updatedAtKey) ?? ''),
    );
  }

  Future<void> save(LocalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameKey, profile.normalizedNickname);
    await prefs.setString(_avatarIconKey, profile.avatarIcon);
    await prefs.setBool(_pendingSyncKey, profile.pendingSync);

    final pendingOperationId = profile.pendingOperationId;
    if (pendingOperationId == null || pendingOperationId.isEmpty) {
      await prefs.remove(_pendingOperationIdKey);
    } else {
      await prefs.setString(_pendingOperationIdKey, pendingOperationId);
    }

    final syncError = profile.syncError;
    if (syncError == null || syncError.isEmpty) {
      await prefs.remove(_syncErrorKey);
    } else {
      await prefs.setString(_syncErrorKey, syncError);
    }

    final updatedAt = profile.updatedAt;
    if (updatedAt == null) {
      await prefs.remove(_updatedAtKey);
    } else {
      await prefs.setString(_updatedAtKey, updatedAt.toIso8601String());
    }
  }
}
