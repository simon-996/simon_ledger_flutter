import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/ai_bookkeeping_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uploads PCM with auth and octet-stream without storing the bytes', () async {
    SharedPreferences.setMockInitialValues({});
    final tokens = TokenStore();
    await tokens.save(const AuthToken(name: 'simon-ledger', value: 'test-token'));
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test', contentType: Headers.jsonContentType));
    final api = ApiClient(tokenStore: tokens, dio: dio);
    RequestOptions? captured;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      captured = options;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'code': 0, 'message': 'ok', 'data': {'text': '早餐花了十八元'},
      }));
    }));
    final text = await AiBookkeepingRepository(api).transcribe(
      'ledger-1', Uint8List.fromList([1, 2, 3, 4]));
    expect(text, '早餐花了十八元');
    expect(captured?.headers['simon-ledger'], 'test-token');
    expect(captured?.contentType, 'application/octet-stream');
    expect(captured?.data, [1, 2, 3, 4]);
  });
}
