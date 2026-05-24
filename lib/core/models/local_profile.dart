import 'package:flutter/material.dart';

class LocalProfile {
  const LocalProfile({required this.nickname, required this.avatarIcon});

  static const defaultProfile = LocalProfile(
    nickname: '我',
    avatarIcon: 'person',
  );

  final String nickname;
  final String avatarIcon;

  String get normalizedNickname {
    final value = nickname.trim();
    return value.isEmpty ? defaultProfile.nickname : value;
  }

  String get personAvatar {
    return switch (avatarIcon) {
      'face' => '🙂',
      'wallet' => '👛',
      'home' => '🏠',
      'star' => '⭐',
      _ => '👤',
    };
  }

  IconData get iconData {
    return switch (avatarIcon) {
      'face' => Icons.face_rounded,
      'wallet' => Icons.account_balance_wallet_rounded,
      'home' => Icons.home_rounded,
      'star' => Icons.star_rounded,
      _ => Icons.person_rounded,
    };
  }

  LocalProfile copyWith({String? nickname, String? avatarIcon}) {
    return LocalProfile(
      nickname: nickname ?? this.nickname,
      avatarIcon: avatarIcon ?? this.avatarIcon,
    );
  }
}
