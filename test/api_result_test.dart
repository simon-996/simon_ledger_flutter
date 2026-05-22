import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/network/api_result.dart';
import 'package:simon_ledger_flutter/core/repositories/auth_repository.dart';

void main() {
  group('ApiResult', () {
    test('does not parse null data for failed responses', () {
      final result = ApiResult<AuthLoginResult>.fromJson({
        'code': 400001,
        'message': '账号或密码错误',
        'data': null,
      }, AuthLoginResult.fromJson);

      expect(result.code, 400001);
      expect(result.message, '账号或密码错误');
      expect(result.data, isNull);
    });

    test('parses data for successful responses', () {
      final result = ApiResult<AuthLoginResult>.fromJson({
        'code': 0,
        'message': 'ok',
        'data': {
          'tokenName': 'simon-ledger',
          'tokenValue': 'token-value',
          'user': {
            'uuid': 'user-1',
            'nickname': 'Simon',
            'email': 'simon@example.com',
            'phone': null,
            'avatar': null,
            'status': 1,
          },
        },
      }, AuthLoginResult.fromJson);

      expect(result.data?.token.name, 'simon-ledger');
      expect(result.data?.user.nickname, 'Simon');
    });
  });
}
