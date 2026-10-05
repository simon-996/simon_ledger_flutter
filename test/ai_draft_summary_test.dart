import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_queue.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_draft_summary.dart';

void main() {
  final ledger = Ledger()
    ..uuid = 'ledger-1'
    ..name = '旅行账本'
    ..baseCurrencyCode = 'CNY'
    ..personUuids = ['p1', 'p2'];
  final people = [
    Person()
      ..uuid = 'p1'
      ..name = '张三',
    Person()
      ..uuid = 'p2'
      ..name = '李四',
  ];

  AiDraftItem item(AiDraft draft, {String? amountInput}) => AiDraftItem(
    uuid: 'draft-1',
    operationId: 'operation-1',
    draft: draft,
    position: 1,
    total: 1,
    amountInput: amountInput,
  );

  AiDraft validDraft({
    String paymentMode = 'PERSON_PAID',
    String? payer = 'p2',
    String participantScope = 'ALL',
    List<String> participantIds = const ['p1', 'p2'],
  }) => AiDraft(
    sourceText: '张三和李四昨天住宿花了400元，李四垫付，所有人都用上了',
    type: 0,
    amount: 400,
    currencyCode: 'CNY',
    categorySuggestion: '居住',
    categoryOriginalSuggestion: '住宿',
    note: '住宿费用',
    happenedAt: DateTime(2026, 10, 4),
    payerPersonUuid: payer,
    personUuids: participantIds,
    unresolvedNames: const [],
    schemaVersion: 2,
    paymentMode: paymentMode,
    participantScope: participantScope,
    splitMode: 'EQUAL',
    fieldSources: const {'splitMode': 'DEFAULT'},
  );

  testWidgets('shows a readable semantic summary and exact day', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftSummary(
            item: item(validDraft()),
            ledger: ledger,
            people: people,
            expenseCategories: const ['居住', '餐饮'],
            incomeCategories: const ['工资'],
            busy: false,
            onEdit: (_) {},
            onConfirm: () async {},
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('支出'), findsOneWidget);
    expect(find.text('CNY 400.00'), findsOneWidget);
    expect(find.text('2026-10-04'), findsOneWidget);
    expect(find.text('居住'), findsOneWidget);
    expect(find.text('李四垫付'), findsOneWidget);
    expect(find.text('全体 2 人承担'), findsOneWidget);
    expect(find.text('默认均摊 · 约 CNY 200.00/人'), findsOneWidget);
    expect(find.textContaining('住宿费用'), findsOneWidget);
    expect(find.textContaining('张三和李四昨天住宿'), findsNothing);

    await tester.tap(find.text('查看原文'));
    await tester.pumpAndSettle();
    expect(find.textContaining('张三和李四昨天住宿花了400元'), findsOneWidget);
  });

  testWidgets(
    'invalid amount and unresolved roles never show stale values as ready',
    (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiDraftSummary(
              item: item(
                validDraft(paymentMode: 'UNKNOWN', payer: null),
                amountInput: '',
              ),
              ledger: ledger,
              people: people,
              expenseCategories: const ['居住', '餐饮'],
              incomeCategories: const ['工资'],
              busy: false,
              onEdit: (_) {},
              onConfirm: () async => confirmed = true,
              onSkip: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('金额待核对'), findsOneWidget);
      expect(find.text('CNY 400.00'), findsNothing);
      expect(find.text('还有 2 项待确认'), findsOneWidget);
      expect(find.text('待选择付款方式'), findsOneWidget);
      expect(find.text('选择付款方式'), findsOneWidget);
      expect(find.text('承担人员'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认记账'))
            .onPressed,
        isNull,
      );
      expect(confirmed, isFalse);
    },
  );

  testWidgets('field edits open only the selected field path', (tester) async {
    String? selectedField;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftSummary(
            item: item(validDraft()),
            ledger: ledger,
            people: people,
            expenseCategories: const ['居住', '餐饮'],
            incomeCategories: const ['工资'],
            busy: false,
            onEdit: (field) => selectedField = field,
            onConfirm: () async {},
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-summary-edit-happenedAt')));
    expect(selectedField, 'happenedAt');
  });

  testWidgets('keeps confirmation visible on a narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: MaterialApp(
          home: Scaffold(
            body: AiDraftSummary(
              item: item(validDraft()),
              ledger: ledger,
              people: people,
              expenseCategories: const ['居住', '餐饮'],
              incomeCategories: const ['工资'],
              busy: false,
              onEdit: (_) {},
              onConfirm: () async {},
              onSkip: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text('确认记账')).dy, lessThan(800));
  });
}
