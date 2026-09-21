import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('preserves a structured optimistic conflict from HTTP 409', () async {
    final client = ApiClient(
      tokenStore: TokenStore(),
      dio: Dio()..httpClientAdapter = _JsonAdapter(_conflictBody),
    );

    try {
      await client.put<Object?>(
        '/api/ledgers/ledger-1/transactions/transaction-1',
        data: {'version': 2},
      );
      fail('expected ApiException');
    } on ApiException catch (error) {
      expect(error.statusCode, 409);
      expect(error.code, 409001);
      expect(error.isConflict, isTrue);
      expect(error.conflict?.entityType.name, 'transaction');
      expect(error.conflict?.entityUuid, 'transaction-1');
      expect(error.conflict?.submittedVersion, 2);
      expect(error.conflict?.remoteVersion, 3);
      expect(error.conflict?.remoteDeleted, isFalse);
      expect(error.conflict?.remoteSnapshot['amount'], 28.5);
    }
  });

  test('keeps malformed conflict data as a normal api exception', () async {
    final client = ApiClient(
      tokenStore: TokenStore(),
      dio: Dio()
        ..httpClientAdapter = _JsonAdapter({
          'code': 409001,
          'message': '数据已被其他设备修改',
          'data': 'invalid-conflict-data',
        }),
    );

    await expectLater(
      client.put<Object?>('/api/auth/me', data: {'version': 1}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.isConflict, 'isConflict', isFalse)
            .having((error) => error.data, 'data', 'invalid-conflict-data'),
      ),
    );
  });

  test('rejects incomplete or incorrectly typed conflict payloads', () async {
    final valid = Map<String, Object?>.from(
      _conflictBody['data']! as Map<String, Object?>,
    );
    final invalidPayloads = <Map<String, Object?>>[
      {...valid}..remove('remoteVersion'),
      {...valid, 'remoteVersion': 0},
      {...valid}..remove('remoteSnapshot'),
      {...valid, 'remoteSnapshot': 'not-a-map'},
      {...valid, 'remoteDeleted': 'false'},
      {
        ...valid,
        'entityType': 'profile',
        'entityUuid': 'user-1',
        'remoteSnapshot': {'uuid': 'user-1', 'version': 3},
      },
      {
        ...valid,
        'remoteSnapshot': {
          'uuid': 'transaction-1',
          'ledgerUuid': 'ledger-1',
          'type': 0,
          'amount': 28.5,
          'currencyCode': 'CNY',
          'category': '餐饮',
          'happenedAt': '2026-08-30T08:00:00Z',
          'version': 3,
        },
      },
    ];

    for (final payload in invalidPayloads) {
      final client = ApiClient(
        tokenStore: TokenStore(),
        dio: Dio()
          ..httpClientAdapter = _JsonAdapter({
            'code': 409001,
            'message': '数据已被其他设备修改',
            'data': payload,
          }),
      );

      await expectLater(
        client.put<Object?>('/api/auth/me', data: {'version': 1}),
        throwsA(
          isA<ApiException>().having(
            (error) => error.isConflict,
            'isConflict',
            isFalse,
          ),
        ),
        reason: 'payload should be rejected: $payload',
      );
    }
  });

  test('clears an expired authenticated session and notifies once', () async {
    SharedPreferences.setMockInitialValues({
      'auth_token_name': 'simon-ledger',
      'auth_token_value': 'expired-token',
    });
    var notifications = 0;
    final client = ApiClient(
      tokenStore: TokenStore(),
      onUnauthorized: () => notifications++,
      dio: Dio()
        ..httpClientAdapter = _JsonAdapter({
          'code': 401001,
          'message': '登录状态已失效',
          'data': null,
        }, statusCode: 401),
    );

    await expectLater(
      client.get<Object?>('/api/ledgers'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      client.get<Object?>('/api/ledgers'),
      throwsA(isA<ApiException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token_value'), isNull);
    expect(notifications, 1);
  });
}

const _conflictBody = <String, Object?>{
  'code': 409001,
  'message': '数据已被其他设备修改',
  'data': {
    'entityType': 'transaction',
    'entityUuid': 'transaction-1',
    'submittedVersion': 2,
    'remoteVersion': 3,
    'remoteDeleted': false,
    'remoteSnapshot': {
      'uuid': 'transaction-1',
      'ledgerUuid': 'ledger-1',
      'type': 0,
      'payerPersonUuid': 'person-1',
      'amount': 28.5,
      'currencyCode': 'CNY',
      'category': '餐饮',
      'note': '早餐',
      'happenedAt': '2026-08-30T08:00:00Z',
      'personUuids': ['person-1'],
      'version': 3,
    },
  },
};

class _JsonAdapter implements HttpClientAdapter {
  const _JsonAdapter(this.body, {this.statusCode = 409});

  final Map<String, Object?> body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
