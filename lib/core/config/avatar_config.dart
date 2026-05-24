class AvatarOption {
  const AvatarOption({required this.key, required this.avatar});

  final String key;
  final String avatar;
}

abstract final class AvatarConfig {
  static const defaultKey = 'person';

  static const options = <AvatarOption>[
    AvatarOption(key: 'person', avatar: '🧑'),
    AvatarOption(key: 'account', avatar: '👤'),
    AvatarOption(key: 'face', avatar: '🙂'),
    AvatarOption(key: 'cool', avatar: '😎'),
    AvatarOption(key: 'developer_1', avatar: '👨‍💻'),
    AvatarOption(key: 'developer_2', avatar: '👩‍💻'),
    AvatarOption(key: 'wallet', avatar: '👛'),
    AvatarOption(key: 'home', avatar: '🏠'),
    AvatarOption(key: 'star', avatar: '⭐'),
    AvatarOption(key: 'avatar_01', avatar: '🐱'),
    AvatarOption(key: 'avatar_02', avatar: '🐶'),
    AvatarOption(key: 'avatar_03', avatar: '🦊'),
    AvatarOption(key: 'avatar_04', avatar: '🐻'),
    AvatarOption(key: 'avatar_05', avatar: '🐼'),
    AvatarOption(key: 'avatar_06', avatar: '🐯'),
    AvatarOption(key: 'avatar_07', avatar: '🦁'),
    AvatarOption(key: 'avatar_08', avatar: '🐷'),
    AvatarOption(key: 'avatar_09', avatar: '🐸'),
    AvatarOption(key: 'avatar_10', avatar: '🐵'),
    AvatarOption(key: 'avatar_11', avatar: '🦝'),
    AvatarOption(key: 'avatar_12', avatar: '🦐'),
    AvatarOption(key: 'avatar_13', avatar: '🦇'),
    AvatarOption(key: 'avatar_14', avatar: '🐌'),
    AvatarOption(key: 'avatar_15', avatar: '🐜'),
  ];

  static Iterable<String> get avatars => options.map((option) => option.avatar);

  static String get defaultAvatar => avatarForKey(defaultKey);

  static String avatarForKey(String value) {
    final key = normalizeKey(value);
    for (final option in options) {
      if (option.key == key) {
        return option.avatar;
      }
    }
    return options.first.avatar;
  }

  static String normalizeKey(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return defaultKey;
    }

    for (final option in options) {
      if (option.key == trimmed) {
        return option.key;
      }
    }

    for (final option in options) {
      if (option.avatar == trimmed) {
        return option.key;
      }
    }

    return defaultKey;
  }

  static String normalizeAvatar(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return defaultAvatar;
    }

    for (final option in options) {
      if (option.avatar == trimmed) {
        return option.avatar;
      }
    }

    for (final option in options) {
      if (option.key == trimmed) {
        return option.avatar;
      }
    }

    return trimmed;
  }
}
