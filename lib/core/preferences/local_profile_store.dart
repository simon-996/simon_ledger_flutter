import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_data_scope.dart';
import '../models/local_profile.dart';

class LocalProfileStore {
  const LocalProfileStore({this.scope = const LocalDataScope.guest()});

  final LocalDataScope scope;

  static const _legacyNicknameKey = 'local_profile.nickname.v1';
  static const _legacyAvatarIconKey = 'local_profile.avatar_icon.v1';
  static const _legacyPendingSyncKey = 'local_profile.pending_sync.v1';
  static const _legacyPendingOperationIdKey =
      'local_profile.pending_operation_id.v1';
  static const _legacySyncErrorKey = 'local_profile.sync_error.v1';
  static const _legacyUpdatedAtKey = 'local_profile.updated_at.v1';
  static const _legacyRemoteVersionKey = 'local_profile.remote_version.v1';

  String _key(String name) => 'local_profile.${scope.storageKey}.$name.v2';

  String get _nicknameKey => _key('nickname');
  String get _avatarIconKey => _key('avatar_icon');
  String get _pendingSyncKey => _key('pending_sync');
  String get _pendingOperationIdKey => _key('pending_operation_id');
  String get _syncErrorKey => _key('sync_error');
  String get _updatedAtKey => _key('updated_at');
  String get _remoteVersionKey => _key('remote_version');

  Future<LocalProfile> read() async {
    final prefs = await SharedPreferences.getInstance();
    final hasScopedProfile =
        prefs.containsKey(_nicknameKey) ||
        prefs.containsKey(_avatarIconKey) ||
        prefs.containsKey(_pendingSyncKey) ||
        prefs.containsKey(_remoteVersionKey);

    final nicknameKey = hasScopedProfile || !scope.isGuest
        ? _nicknameKey
        : _legacyNicknameKey;
    final avatarIconKey = hasScopedProfile || !scope.isGuest
        ? _avatarIconKey
        : _legacyAvatarIconKey;
    final pendingSyncKey = hasScopedProfile || !scope.isGuest
        ? _pendingSyncKey
        : _legacyPendingSyncKey;
    final pendingOperationIdKey = hasScopedProfile || !scope.isGuest
        ? _pendingOperationIdKey
        : _legacyPendingOperationIdKey;
    final syncErrorKey = hasScopedProfile || !scope.isGuest
        ? _syncErrorKey
        : _legacySyncErrorKey;
    final updatedAtKey = hasScopedProfile || !scope.isGuest
        ? _updatedAtKey
        : _legacyUpdatedAtKey;
    final remoteVersionKey = hasScopedProfile || !scope.isGuest
        ? _remoteVersionKey
        : _legacyRemoteVersionKey;

    return LocalProfile(
      nickname:
          prefs.getString(nicknameKey) ?? LocalProfile.defaultProfile.nickname,
      avatarIcon:
          prefs.getString(avatarIconKey) ??
          LocalProfile.defaultProfile.avatarIcon,
      pendingSync: prefs.getBool(pendingSyncKey) ?? false,
      pendingOperationId: prefs.getString(pendingOperationIdKey),
      syncError: prefs.getString(syncErrorKey),
      updatedAt: DateTime.tryParse(prefs.getString(updatedAtKey) ?? ''),
      remoteVersion: prefs.getInt(remoteVersionKey) ?? 1,
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
    await prefs.setInt(_remoteVersionKey, profile.remoteVersion);
  }
}
