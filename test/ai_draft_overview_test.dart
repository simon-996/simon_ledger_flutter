import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_queue.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_draft_overview.dart';

void main() {
  testWidgets('lists drafts in source order with readiness and selection', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final people = [
      Person()
        ..uuid = 'p1'
        ..name = '张三',
    ];
    final today = DateTime.now();
    final items = [
      AiDraftItem(
        uuid: 'draft-first',
        operationId: 'operation-first',
        position: 1,
        total: 2,
        draft: AiDraft(
          sourceText: '早餐18元',
          type: 0,
          amount: 18,
          currencyCode: 'CNY',
          categorySuggestion: '餐饮',
          happenedAt: today,
          payerPersonUuid: 'p1',
          personUuids: const ['p1'],
          unresolvedNames: const [],
          schemaVersion: 2,
          paymentMode: 'PERSON_PAID',
          participantScope: 'SPECIFIED',
        ),
      ),
      AiDraftItem(
        uuid: 'draft-second',
        operationId: 'operation-second',
        position: 2,
        total: 2,
        draft: AiDraft(
          sourceText: '住宿400元',
          type: 0,
          amount: 400,
          currencyCode: 'CNY',
          categorySuggestion: '居住',
          happenedAt: today,
          personUuids: const ['p1'],
          unresolvedNames: const [],
          schemaVersion: 2,
          paymentMode: 'UNKNOWN',
          participantScope: 'SPECIFIED',
        ),
      ),
    ];
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftOverview(
            items: items,
            selectedUuid: 'draft-first',
            ledger: ledger,
            people: people,
            expenseCategories: const ['餐饮', '居住'],
            incomeCategories: const ['工资'],
            busy: false,
            failedUuids: const {},
            onSelect: (uuid) => selected = uuid,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai-draft-overview-draft-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-draft-overview-draft-second')),
      findsOneWidget,
    );
    expect(find.text('可确认'), findsOneWidget);
    expect(find.text('待补充'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('ai-draft-overview-draft-second')),
    );
    expect(selected, 'draft-second');
  });

  testWidgets('shows busy and failed save statuses', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '张三';
    final item = AiDraftItem(
      uuid: 'draft-1',
      operationId: 'operation-1',
      position: 1,
      total: 2,
      draft: AiDraft(
        sourceText: '早餐18元',
        type: 0,
        amount: 18,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        happenedAt: DateTime.now(),
        payerPersonUuid: 'p1',
        personUuids: const ['p1'],
        unresolvedNames: const [],
        schemaVersion: 2,
        paymentMode: 'PERSON_PAID',
        participantScope: 'SPECIFIED',
      ),
    );

    Future<void> show({
      required bool busy,
      Set<String> failed = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiDraftOverview(
              items: [item],
              selectedUuid: item.uuid,
              ledger: ledger,
              people: [person],
              expenseCategories: const ['餐饮'],
              incomeCategories: const ['工资'],
              busy: busy,
              failedUuids: failed,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(busy: true);
    expect(find.text('保存中'), findsOneWidget);
    await show(busy: false, failed: {item.uuid});
    expect(find.text('保存失败'), findsOneWidget);
  });
}
