import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/ai_bookkeeping_repository.dart';

class FakeAiApiClient extends ApiClient {
  FakeAiApiClient() : super(tokenStore: TokenStore());

  final paths = <String>[];
  bool textAvailable = true;
  Object? postedData;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    paths.add(path);
    return fromJson!({
      'textAvailable': textAvailable,
      'voiceAvailable': false,
      'reason': null,
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

class _TestAccountScope extends Notifier<LocalDataScope> {
  @override
  LocalDataScope build() => const LocalDataScope.account('account-a');

  void switchAccount() => state = const LocalDataScope.account('account-b');
}

final _testAccountScopeProvider =
    NotifierProvider<_TestAccountScope, LocalDataScope>(_TestAccountScope.new);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('explicit category lists preserve a deliberately empty type', () async {
    final api = FakeAiApiClient();
    await AiBookkeepingRepository(api).parse(
      'ledger-1',
      '作品出售收入',
      '+08:00',
      expenseCategories: const [],
      incomeCategories: const ['版权授权'],
    );
    final body = api.postedData as Map<String, dynamic>;
    expect(body['expenseCategories'], isEmpty);
    expect(body['incomeCategories'], ['版权授权']);
  });
  test(
    'parse sends current custom categories as context without keyword rules',
    () async {
      SharedPreferences.setMockInitialValues({
        'transaction_categories.expense.v1': ['养猫', '学习进修'],
        'transaction_categories.income.v1': ['稿费'],
      });
      final api = FakeAiApiClient();
      await AiBookkeepingRepository(api).parse('ledger-1', '给猫买了罐头', '+08:00');
      final body = api.postedData as Map<String, dynamic>;
      expect(
        body['expenseCategories'],
        containsAll(['餐饮', '交通', '养猫', '学习进修']),
      );
      expect(body['incomeCategories'], containsAll(['工资', '稿费']));
      expect(body['text'], '给猫买了罐头');
    },
  );

  test(
    'switching accounts reloads AI capability for the same shared ledger',
    () async {
      final api = FakeAiApiClient()..textAvailable = false;
      final container = ProviderContainer(
        overrides: [
          activeLocalDataScopeProvider.overrideWith(
            (ref) => ref.watch(_testAccountScopeProvider),
          ),
          aiBookkeepingRepositoryProvider.overrideWithValue(
            AiBookkeepingRepository(api),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        aiCapabilityProvider('shared-ledger'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        (await container.read(
          aiCapabilityProvider('shared-ledger').future,
        )).textAvailable,
        isFalse,
      );
      api.textAvailable = true;
      container.read(_testAccountScopeProvider.notifier).switchAccount();
      expect(
        (await container.read(
          aiCapabilityProvider('shared-ledger').future,
        )).textAvailable,
        isTrue,
      );
      expect(api.paths.length, 2);
    },
  );

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
  });
}
