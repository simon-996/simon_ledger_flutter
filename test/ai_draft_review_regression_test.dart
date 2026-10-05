import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_draft_review.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final ledger = Ledger()
    ..uuid = 'ledger-1'
    ..name = '旅行'
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
  AiDraft draft({List<AiDraftIssue> issues = const []}) => AiDraft(
    sourceText: '住宿400，张三垫付，大家使用。',
    type: 0,
    amount: 400,
    currencyCode: 'CNY',
    categorySuggestion: '居住',
    personUuids: const ['p1', 'p2'],
    unresolvedNames: const [],
    schemaVersion: 2,
    paymentMode: 'PERSON_PAID',
    payerPersonUuid: 'p1',
    participantScope: 'ALL',
    happenedAt: DateTime(2026, 10, 4),
    issues: issues,
  );

  Future<void> showReview(
    WidgetTester tester,
    AiDraft value,
    Future<void> Function(AiDraft) onConfirm, {
    String? field,
    void Function(AiDraft, String)? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: value,
            ledger: ledger,
            people: people,
            position: 1,
            total: 1,
            busy: false,
            initialField: field,
            onConfirm: onConfirm,
            onChanged: onChanged,
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an explicit time edit survives review with time precision', (
    tester,
  ) async {
    AiDraft? saved;
    await showReview(
      tester,
      draft(),
      (value) async => saved = value,
      field: 'happenedAt',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('transaction-date-control')),
    );
    await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-hour-input')),
      '14',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-minute-input')),
      '35',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved?.happenedAt, DateTime(2026, 10, 4, 14, 35));
    expect(saved?.datePrecision, 'TIME');
    expect(saved?.fieldSources['happenedAt'], 'USER');
  });

  testWidgets('day-only edit persists once without inventing time precision', (
    tester,
  ) async {
    AiDraft? saved;
    final changes = <AiDraft>[];
    await showReview(
      tester,
      draft(),
      (value) async => saved = value,
      field: 'happenedAt',
      onChanged: (value, _) => changes.add(value),
    );
    expect(find.textContaining('未指定时间'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('transaction-date-control')),
    );
    await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前天'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    expect(changes.single.datePrecision, 'DAY');
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved?.datePrecision, 'DAY');
    expect(saved?.fieldSources['happenedAt'], 'USER');
    expect(
      DateUtils.isSameDay(
        saved?.happenedAt,
        DateUtils.addDaysToDate(DateTime.now(), -2),
      ),
      isTrue,
    );
  });

  testWidgets('a supported currency conflict can be deliberately reconfirmed', (
    tester,
  ) async {
    AiDraft? saved;
    await showReview(
      tester,
      draft(
        issues: const [
          AiDraftIssue(
            id: 'currency-conflict',
            field: 'currencyCode',
            code: 'CONFLICTING_FIELDS',
          ),
        ],
      ),
      (value) async => saved = value,
      field: 'currencyCode',
    );
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved, isNull);

    final action = find.byKey(const ValueKey('ai-confirm-currency'));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved?.currencyCode, 'CNY');
    expect(saved?.amount, 400);
    expect(saved?.issues, isEmpty);
    expect(saved?.fieldSources['currencyCode'], 'USER');
  });

  testWidgets(
    'an unknown exclusion can be explicitly cancelled without removing another person',
    (tester) async {
      AiDraft? saved;
      await showReview(
        tester,
        draft(
          issues: const [
            AiDraftIssue(
              id: 'excluded',
              field: 'excludedParticipants',
              code: 'PERSON_NOT_FOUND',
              sourceText: '小陈',
            ),
          ],
        ),
        (value) async => saved = value,
        field: 'excludedParticipants',
      );
      final action = find.byKey(const ValueKey('ai-cancel-exclusion-excluded'));
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认记账'));
      await tester.pumpAndSettle();
      expect(saved?.personUuids, ['p1', 'p2']);
      expect(saved?.participantScope, 'SPECIFIED');
      expect(saved?.issues, isEmpty);
      expect(saved?.fieldSources['excludedParticipants'], 'USER');
    },
  );

  testWidgets('a corrected amount is stored with its user source', (
    tester,
  ) async {
    AiDraft? saved;
    await showReview(
      tester,
      draft(),
      (value) async => saved = value,
      field: 'amount',
    );
    await tester.enterText(find.widgetWithText(TextField, '金额'), '400.12');
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved?.amount, 400.12);
    expect(saved?.fieldSources['amount'], 'USER');
  });

  testWidgets('an edited amount with hidden extra decimals cannot be saved', (
    tester,
  ) async {
    AiDraft? saved;
    await showReview(
      tester,
      draft(),
      (value) async => saved = value,
      field: 'amount',
    );
    await tester.enterText(find.widgetWithText(TextField, '金额'), '400.123');
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('金额最多保留 2 位小数，请使用普通数字'), findsOneWidget);
  });

  testWidgets('opening an imprecise draft does not silently round its amount', (
    tester,
  ) async {
    AiDraft? saved;
    await showReview(
      tester,
      draft().copyWith(amount: 400.123),
      (value) async => saved = value,
      field: 'amount',
    );
    final input = tester.widget<TextField>(
      find.widgetWithText(TextField, '金额'),
    );
    expect(input.controller?.text, '400.123');
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('金额最多保留 2 位小数，请使用普通数字'), findsOneWidget);
  });
}
