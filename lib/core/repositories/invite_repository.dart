import '../network/api_client.dart';

class LedgerInvite {
  const LedgerInvite({
    required this.code,
    required this.ledgerUuid,
    required this.ledgerName,
    required this.ledgerBaseCurrencyCode,
    required this.ledgerMemberCount,
    required this.ledgerMembers,
    required this.role,
    required this.maxUses,
    required this.usedCount,
    required this.expiresAt,
    required this.expired,
    required this.disabled,
  });

  final String code;
  final String ledgerUuid;
  final String ledgerName;
  final String ledgerBaseCurrencyCode;
  final int ledgerMemberCount;
  final List<LedgerInviteMember> ledgerMembers;
  final String role;
  final int? maxUses;
  final int usedCount;
  final DateTime expiresAt;
  final bool expired;
  final bool disabled;

  bool get exhausted => maxUses != null && usedCount >= maxUses!;

  bool get isUsable => !expired && !disabled && !exhausted;

  String? get unavailableReason {
    if (disabled) return '该邀请码已停用';
    if (expired) return '该邀请码已过期';
    if (exhausted) return '该邀请码的使用次数已达上限';
    return null;
  }

  int? get remainingUses {
    final limit = maxUses;
    if (limit == null) return null;
    return (limit - usedCount).clamp(0, limit);
  }

  String get ledgerDisplayCode {
    final normalizedUuid = ledgerUuid.trim();
    final suffix = normalizedUuid.length <= 8
        ? normalizedUuid
        : normalizedUuid.substring(normalizedUuid.length - 8);
    return 'Simon-$suffix';
  }

  factory LedgerInvite.fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    final members = switch (map['ledgerMembers']) {
      final List<Object?> values =>
        values
            .whereType<Map<String, dynamic>>()
            .map(LedgerInviteMember.fromJson)
            .toList(),
      _ => const <LedgerInviteMember>[],
    };
    return LedgerInvite(
      code: map['code'].toString(),
      ledgerUuid: map['ledgerUuid'].toString(),
      ledgerName: map['ledgerName'].toString(),
      ledgerBaseCurrencyCode:
          map['ledgerBaseCurrencyCode']?.toString() ?? 'CNY',
      ledgerMemberCount:
          (map['ledgerMemberCount'] as num?)?.toInt() ?? members.length,
      ledgerMembers: members,
      role: map['role'].toString(),
      maxUses: (map['maxUses'] as num?)?.toInt(),
      usedCount: (map['usedCount'] as num?)?.toInt() ?? 0,
      expiresAt:
          DateTime.tryParse(map['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
      expired: map['expired'] == true,
      disabled: map['disabled'] == true,
    );
  }
}

class LedgerInviteMember {
  const LedgerInviteMember({
    required this.nickname,
    required this.avatar,
    required this.role,
  });

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

  factory LedgerInviteMember.fromJson(Map<String, dynamic> map) {
    return LedgerInviteMember(
      nickname: map['nickname']?.toString(),
      avatar: map['avatar']?.toString(),
      role: map['role']?.toString(),
    );
  }
}

class InviteRepository {
  const InviteRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<LedgerInvite> createInvite(String ledgerUuid) {
    final expiresAt = DateTime.now().add(const Duration(days: 7));
    return _apiClient.post<LedgerInvite>(
      '/api/ledgers/$ledgerUuid/invites',
      data: {
        'role': 'editor',
        'maxUses': 20,
        'expiresAt': expiresAt.toIso8601String(),
      },
      idempotencyKey:
          'create-invite-$ledgerUuid-${DateTime.now().microsecondsSinceEpoch}',
      fromJson: LedgerInvite.fromJson,
    );
  }

  Future<LedgerInvite> join(String code) {
    final normalizedCode = code.trim().toUpperCase();
    return _apiClient.post<LedgerInvite>(
      '/api/invites/$normalizedCode/join',
      idempotencyKey: 'join-invite-$normalizedCode',
      fromJson: LedgerInvite.fromJson,
    );
  }

  Future<LedgerInvite> preview(String code) {
    final normalizedCode = code.trim().toUpperCase();
    return _apiClient.get<LedgerInvite>(
      '/api/invites/$normalizedCode',
      fromJson: LedgerInvite.fromJson,
    );
  }
}
