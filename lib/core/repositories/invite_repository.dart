import 'dart:math';

import '../database/database_service.dart';
import '../models/invite_join_result.dart';
import '../network/api_client.dart';
import '../network/token_store.dart';
import '../services/invite_join_cache.dart';

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
  InviteRepository(
    this._apiClient, {
    DatabaseService? database,
    TokenStore? tokenStore,
    InviteJoinCache? joinCache,
  }) : _database = database,
       _tokenStore = tokenStore,
       _joinCache =
           joinCache ?? (database == null ? null : InviteJoinCache(database));

  final ApiClient _apiClient;
  final DatabaseService? _database;
  final TokenStore? _tokenStore;
  final InviteJoinCache? _joinCache;

  Future<LedgerInvite?> getCurrentInvite(String ledgerUuid) {
    return _apiClient.get<LedgerInvite?>(
      '/api/ledgers/$ledgerUuid/invites/current',
      fromJson: (json) => json == null ? null : LedgerInvite.fromJson(json),
    );
  }

  Future<LedgerInvite> regenerateInvite(
    String ledgerUuid, {
    required int days,
    required int maxUses,
  }) {
    return _apiClient.post<LedgerInvite>(
      '/api/ledgers/$ledgerUuid/invites/regenerate',
      data: {'role': 'editor', 'days': days, 'maxUses': maxUses},
      idempotencyKey:
          'regenerate-invite-$ledgerUuid-${DateTime.now().microsecondsSinceEpoch}',
      fromJson: LedgerInvite.fromJson,
    );
  }

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

  Future<LedgerInvite> join(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    final session = await _captureSession(_tokenStore);
    final result = await _apiClient.post<InviteJoinResult>(
      '/api/invites/$normalizedCode/join',
      idempotencyKey: 'join-invite-v2-${_newUuid()}',
      fromJson: InviteJoinResult.fromJson,
    );
    await _assertJoinSessionUnchanged(_tokenStore, session);
    if (_joinCache != null) {
      await _joinCache.apply(result, accountUuid: session?.accountUuid);
    } else {
      await _database?.restoreLedgerAccess(result.invite.ledgerUuid);
    }
    return result.invite;
  }

  Future<LedgerInvite> preview(String code) {
    final normalizedCode = code.trim().toUpperCase();
    return _apiClient.get<LedgerInvite>(
      '/api/invites/$normalizedCode',
      fromJson: LedgerInvite.fromJson,
    );
  }
}

class _JoinSession {
  const _JoinSession({this.token, this.accountUuid});

  final AuthToken? token;
  final String? accountUuid;
}

Future<_JoinSession?> _captureSession(TokenStore? tokenStore) async {
  if (tokenStore == null) return null;
  return _JoinSession(
    token: await tokenStore.read(),
    accountUuid: await tokenStore.readAccountUuid(),
  );
}

Future<void> _assertJoinSessionUnchanged(
  TokenStore? tokenStore,
  _JoinSession? before,
) async {
  if (tokenStore == null || before == null) return;
  final after = _JoinSession(
    token: await tokenStore.read(),
    accountUuid: await tokenStore.readAccountUuid(),
  );
  final beforeToken = before.token;
  final afterToken = after.token;
  final tokenChanged =
      beforeToken?.name != afterToken?.name ||
      beforeToken?.value != afterToken?.value;
  if (tokenChanged || before.accountUuid != after.accountUuid) {
    throw StateError('登录账号已切换，请重试加入账本');
  }
}

String _newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
  final values = hex.toList();
  return '${values.sublist(0, 4).join()}-'
      '${values.sublist(4, 6).join()}-'
      '${values.sublist(6, 8).join()}-'
      '${values.sublist(8, 10).join()}-'
      '${values.sublist(10).join()}';
}
