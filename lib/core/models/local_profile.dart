import '../config/avatar_config.dart';

class LocalProfile {
  const LocalProfile({
    required this.nickname,
    required this.avatarIcon,
    this.pendingSync = false,
    this.pendingOperationId,
    this.syncError,
    this.updatedAt,
  });

  static const defaultProfile = LocalProfile(
    nickname: '我',
    avatarIcon: AvatarConfig.defaultKey,
  );

  final String nickname;
  final String avatarIcon;
  final bool pendingSync;
  final String? pendingOperationId;
  final String? syncError;
  final DateTime? updatedAt;

  String get normalizedNickname {
    final value = nickname.trim();
    return value.isEmpty ? defaultProfile.nickname : value;
  }

  String get personAvatar => AvatarConfig.avatarForKey(avatarIcon);

  LocalProfile copyWith({
    String? nickname,
    String? avatarIcon,
    bool? pendingSync,
    Object? pendingOperationId = _sentinel,
    Object? syncError = _sentinel,
    Object? updatedAt = _sentinel,
  }) {
    return LocalProfile(
      nickname: nickname ?? this.nickname,
      avatarIcon: avatarIcon ?? this.avatarIcon,
      pendingSync: pendingSync ?? this.pendingSync,
      pendingOperationId: identical(pendingOperationId, _sentinel)
          ? this.pendingOperationId
          : pendingOperationId as String?,
      syncError: identical(syncError, _sentinel)
          ? this.syncError
          : syncError as String?,
      updatedAt: identical(updatedAt, _sentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

const _sentinel = Object();
