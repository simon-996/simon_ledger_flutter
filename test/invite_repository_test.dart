import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/invite_repository.dart';

void main() {
  test('invite preview parses ledger details and shared members', () {
    final invite = LedgerInvite.fromJson(_inviteJson);

    expect(invite.code, 'ABCD1234');
    expect(invite.ledgerBaseCurrencyCode, 'USD');
    expect(invite.ledgerMemberCount, 2);
    expect(invite.ledgerMembers.first.displayName, 'Simon');
    expect(invite.ledgerMembers.last.displayAvatar, '👤');
    expect(invite.remainingUses, 18);
    expect(invite.isUsable, isTrue);
    expect(invite.ledgerDisplayCode, 'Simon-12345678');
  });

  test(
    'preview normalizes the invitation code before requesting details',
    () async {
      final apiClient = _InviteApiClient();
      final repository = InviteRepository(apiClient);

      await repository.preview('  abcd1234 ');

      expect(apiClient.requestedPath, '/api/invites/ABCD1234');
    },
  );

  test('exhausted invite cannot be joined', () {
    final invite = LedgerInvite.fromJson({..._inviteJson, 'usedCount': 20});

    expect(invite.isUsable, isFalse);
    expect(invite.unavailableReason, '该邀请码的使用次数已达上限');
  });
}

final _inviteJson = <String, dynamic>{
  'code': 'ABCD1234',
  'ledgerUuid': '00000000000000000000000012345678',
  'ledgerName': '旅行账本',
  'ledgerBaseCurrencyCode': 'USD',
  'ledgerMemberCount': 2,
  'ledgerMembers': [
    {'nickname': 'Simon', 'avatar': '😎', 'role': 'owner'},
    {'nickname': '', 'avatar': '', 'role': 'editor'},
  ],
  'role': 'editor',
  'maxUses': 20,
  'usedCount': 2,
  'expiresAt': '2026-06-09T20:00:00',
  'expired': false,
  'disabled': false,
};

class _InviteApiClient extends ApiClient {
  _InviteApiClient() : super(tokenStore: TokenStore());

  String? requestedPath;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    requestedPath = path;
    return fromJson!(_inviteJson);
  }
}
