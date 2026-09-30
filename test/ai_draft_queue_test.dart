import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  AiDraft sample(String source) => AiDraft(
    sourceText: source,
    type: 0,
    amount: 18,
    currencyCode: 'CNY',
    personUuids: const [],
    unresolvedNames: const [],
  );

  test('keeps pending drafts separate by account and ledger after restart', () async {
    final queue = AiDraftQueue(scope: const LocalDataScope.account('alice'), loadTransactions: (_) async => []);
    await queue.add('ledger-a', [sample('早餐18元'), sample('午饭32元')]);

    expect((await AiDraftQueue(scope: const LocalDataScope.account('alice'), loadTransactions: (_) async => [])
        .load('ledger-a')).map((item) => item.draft.sourceText).toList(),
        ['早餐18元', '午饭32元']);
    expect(await AiDraftQueue(scope: const LocalDataScope.account('bob'), loadTransactions: (_) async => [])
        .load('ledger-a'), isEmpty);
    expect(await queue.load('ledger-b'), isEmpty);
  });

  test('removes an already saved draft on recovery without resubmitting it', () async {
    final queue = AiDraftQueue(scope: const LocalDataScope.account('alice'), loadTransactions: (_) async => []);
    await queue.add('ledger-a', [sample('早餐18元')]);
    final pending = (await queue.load('ledger-a')).single;
    final saved = TransactionRecord()
      ..uuid = pending.uuid
      ..clientOperationId = pending.operationId;
    final restarted = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [saved],
    );
    expect(await restarted.load('ledger-a'), isEmpty);
    expect(await queue.load('ledger-a'), isEmpty);
  });

  test('keeps unfinished text input scoped to account and ledger', () async {
    final queue = AiDraftQueue(scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => []);
    await queue.writeInput('ledger-a', '早餐十八元');

    expect(await AiDraftQueue(scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => []).readInput('ledger-a'), '早餐十八元');
    expect(await queue.readInput('ledger-b'), isEmpty);
    expect(await AiDraftQueue(scope: const LocalDataScope.account('bob'),
      loadTransactions: (_) async => []).readInput('ledger-a'), isEmpty);
  });
}
