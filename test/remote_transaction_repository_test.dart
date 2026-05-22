import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/repositories/transaction_repository.dart';

void main() {
  group('RemoteTransactionRepository', () {
    test('loads all transaction pages for a ledger', () async {
      final apiClient = _FakeApiClient([
        {
          'page': 1,
          'pageSize': 2,
          'total': 3,
          'records': [_transactionJson('tx-1'), _transactionJson('tx-2')],
        },
        {
          'page': 2,
          'pageSize': 2,
          'total': 3,
          'records': [_transactionJson('tx-3')],
        },
      ]);
      final repository = RemoteTransactionRepository(apiClient);

      final transactions = await repository.getTransactionsForLedger(
        'ledger-1',
      );

      expect(transactions.map((transaction) => transaction.uuid), [
        'tx-1',
        'tx-2',
        'tx-3',
      ]);
      expect(apiClient.requestedPages, [1, 2]);
    });
  });
}

Map<String, Object?> _transactionJson(String uuid) {
  return {
    'uuid': uuid,
    'ledgerUuid': 'ledger-1',
    'type': 0,
    'amount': 12.5,
    'currencyCode': 'CNY',
    'category': '餐饮',
    'note': '',
    'personUuids': ['person-1'],
    'happenedAt': '2026-05-22T12:00:00',
    'version': 1,
  };
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this._pages) : super(tokenStore: TokenStore());

  final List<Map<String, Object?>> _pages;
  final List<int> requestedPages = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    requestedPages.add(queryParameters?['page'] as int);
    return fromJson!(_pages.removeAt(0));
  }
}
