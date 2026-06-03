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

  test(
    'current invite returns null when server has no usable invite',
    () async {
      final apiClient = _InviteApiClient(nextGetJson: null);
      final repository = InviteRepository(apiClient);

      final invite = await repository.getCurrentInvite('ledger-uuid');

      expect(invite, isNull);
      expect(
        apiClient.requestedPath,
        '/api/ledgers/ledger-uuid/invites/current',
      );
    },
  );

  test('regenerate invite sends selected days and max uses', () async {
    final apiClient = _InviteApiClient();
    final repository = InviteRepository(apiClient);

    await repository.regenerateInvite('ledger-uuid', days: 3, maxUses: 5);

    expect(
      apiClient.requestedPath,
      '/api/ledgers/ledger-uuid/invites/regenerate',
    );
    expect(apiClient.requestedData, {
      'role': 'editor',
      'days': 3,
      'maxUses': 5,
    });
    expect(apiClient.requestedIdempotencyKey, startsWith('regenerate-invite-'));
  });

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

const _defaultGetJson = Object();

class _InviteApiClient extends ApiClient {
  _InviteApiClient({this.nextGetJson = _defaultGetJson})
    : super(tokenStore: TokenStore());

  final Object? nextGetJson;
  String? requestedPath;
  Object? requestedData;
  String? requestedIdempotencyKey;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    requestedPath = path;
    final json = identical(nextGetJson, _defaultGetJson)
        ? _inviteJson
        : nextGetJson;
    return fromJson!(json);
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    requestedPath = path;
    requestedData = data;
    requestedIdempotencyKey = idempotencyKey;
    return fromJson!(_inviteJson);
  }
}
