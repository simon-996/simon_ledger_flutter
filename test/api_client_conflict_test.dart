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
    'remoteSnapshot': {'uuid': 'transaction-1', 'amount': 28.5, 'version': 3},
  },
};

class _JsonAdapter implements HttpClientAdapter {
  const _JsonAdapter(this.body);

  final Map<String, Object?> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      409,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
