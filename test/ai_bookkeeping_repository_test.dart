import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/ai_bookkeeping_repository.dart';

class FakeAiApiClient extends ApiClient {
  FakeAiApiClient() : super(tokenStore: TokenStore());

  final paths = <String>[];
  Object? postedData;
  int? capabilityVersion;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    paths.add(path);
    return fromJson!({
      'textAvailable': true,
      'voiceAvailable': false,
      'reason': null,
      if (capabilityVersion != null) 'draftSchemaVersion': capabilityVersion,
    });
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    paths.add(path);
    postedData = data;
    return fromJson!({
      'entries': [
        {
          'sourceText': '早餐18元',
          'type': 0,
          'amount': 18.0,
          'currencyCode': 'CNY',
          'personUuids': [],
          'unresolvedNames': [],
        },
        {
          'sourceText': '午饭32元',
          'type': 0,
          'amount': 32.0,
          'currencyCode': 'CNY',
          'personUuids': [],
          'unresolvedNames': [],
        },
      ],
    });
  }
}

void main() {
  test('decodes capability and ordered multi-draft parse response', () async {
    final api = FakeAiApiClient();
    final repo = AiBookkeepingRepository(api);
    final capability = await repo.capability('ledger-1');
    final drafts = await repo.parse('ledger-1', '早餐18元，午饭32元', 'Asia/Shanghai');
    expect(capability.textAvailable, isTrue);
    expect(capability.voiceAvailable, isFalse);
    expect(drafts.map((draft) => draft.sourceText), ['早餐18元', '午饭32元']);
    expect(api.paths, [
      '/api/ledgers/ledger-1/ai-bookkeeping/capability',
      '/api/ledgers/ledger-1/ai-bookkeeping/parse',
    ]);
    expect(capability.draftSchemaVersion, 1);
    expect(api.postedData, {'text': '早餐18元，午饭32元', 'zone': 'Asia/Shanghai'});
  });

  test(
    'sends v2 with ledger categories only when explicitly negotiated',
    () async {
      final api = FakeAiApiClient()..capabilityVersion = 2;
      final repo = AiBookkeepingRepository(api);
      final capability = await repo.capability('ledger-1');
      await repo.parse(
        'ledger-1',
        '住宿400',
        'Asia/Shanghai',
        schemaVersion: capability.draftSchemaVersion,
        expenseCategories: const ['居住', '交通'],
        incomeCategories: const ['工资'],
      );
      expect(api.postedData, {
        'text': '住宿400',
        'zone': 'Asia/Shanghai',
        'schemaVersion': 2,
        'expenseCategories': ['居住', '交通'],
        'incomeCategories': ['工资'],
      });
    },
  );
}
