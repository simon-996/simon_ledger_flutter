import '../network/api_client.dart';

class LedgerInvite {
  const LedgerInvite({
    required this.code,
    required this.ledgerUuid,
    required this.ledgerName,
    required this.role,
    required this.expiresAt,
  });

  final String code;
  final String ledgerUuid;
  final String ledgerName;
  final String role;
  final DateTime expiresAt;

  factory LedgerInvite.fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return LedgerInvite(
      code: map['code'].toString(),
      ledgerUuid: map['ledgerUuid'].toString(),
      ledgerName: map['ledgerName'].toString(),
      role: map['role'].toString(),
      expiresAt:
          DateTime.tryParse(map['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
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
    final normalizedCode = code.trim();
    return _apiClient.post<LedgerInvite>(
      '/api/invites/$normalizedCode/join',
      idempotencyKey: 'join-invite-$normalizedCode',
      fromJson: LedgerInvite.fromJson,
    );
  }
}
