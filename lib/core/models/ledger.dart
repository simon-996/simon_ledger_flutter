class Ledger {
  int id = 0;

  late String uuid;

  late String name;

  late String baseCurrencyCode;

  // Rate to convert baseCurrency to CNY (e.g. if USD, rate might be 7.2)
  double exchangeRateToCNY = 1.0;

  // Storing UUIDs of people associated with this ledger
  List<String> personUuids = [];

  int sortOrder = 0;

  bool isDeleted = false; // Soft delete flag

  String? role;

  int memberCount = 1;

  List<LedgerMemberSummary> members = [];

  String? syncedRemoteUuid;

  bool get isShared => memberCount > 1 || members.length > 1;

  bool get isLocalTemporary => !_looksLikeRemoteUuid(uuid);

  bool get hasSyncedRemoteCopy =>
      syncedRemoteUuid != null && syncedRemoteUuid!.isNotEmpty;

  String get displayCode {
    final normalizedUuid = uuid.trim();
    final suffix = normalizedUuid.length <= 8
        ? normalizedUuid
        : normalizedUuid.substring(normalizedUuid.length - 8);
    return 'Simon-$suffix';
  }

  String get displayNameWithCode => '$name · $displayCode';

  bool _looksLikeRemoteUuid(String value) {
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value);
  }
}

class LedgerMemberSummary {
  LedgerMemberSummary({
    required this.uuid,
    this.userUuid,
    this.nickname,
    this.avatar,
    this.role,
  });

  final String uuid;
  final String? userUuid;
  final String? nickname;
  final String? avatar;
  final String? role;

  String get displayName {
    final value = nickname?.trim();
    return value == null || value.isEmpty ? '成员' : value;
  }

  String get displayAvatar {
    final value = avatar?.trim();
    return value == null || value.isEmpty ? '👤' : value;
  }
}
