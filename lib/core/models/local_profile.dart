import '../config/avatar_config.dart';

class LocalProfile {
  const LocalProfile({required this.nickname, required this.avatarIcon});

  static const defaultProfile = LocalProfile(
    nickname: '我',
    avatarIcon: AvatarConfig.defaultKey,
  );

  final String nickname;
  final String avatarIcon;

  String get normalizedNickname {
    final value = nickname.trim();
    return value.isEmpty ? defaultProfile.nickname : value;
  }

  String get personAvatar => AvatarConfig.avatarForKey(avatarIcon);

  LocalProfile copyWith({String? nickname, String? avatarIcon}) {
    return LocalProfile(
      nickname: nickname ?? this.nickname,
      avatarIcon: avatarIcon ?? this.avatarIcon,
    );
  }
}
