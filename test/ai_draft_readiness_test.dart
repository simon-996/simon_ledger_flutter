import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_readiness.dart';

void main() {
  final today = DateTime(2026, 10, 5, 15);

  AiDraft draft({
    String paymentMode = 'PERSON_PAID',
    String? payer = 'p1',
    int schemaVersion = 2,
    String participantScope = 'SPECIFIED',
    DateTime? happenedAt,
    String splitMode = 'EQUAL',
    List<AiDraftIssue> issues = const [],
  }) => AiDraft(
    sourceText: '张三昨天住宿400',
    type: 0,
    amount: 400,
    currencyCode: 'CNY',
    categorySuggestion: '居住',
    personUuids: const ['p1'],
    unresolvedNames: const [],
    schemaVersion: schemaVersion,
    paymentMode: paymentMode,
    payerPersonUuid: payer,
    participantScope: participantScope,
    splitMode: splitMode,
    happenedAt: happenedAt ?? DateTime(2026, 10, 4),
    issues: issues,
  );

  List<String> check(AiDraft value, {String? amountInput}) =>
      aiDraftBlockingFields(
        value,
        activePersonIds: const {'p1', 'p2'},
        categories: const ['居住', '餐饮'],
        supportedCurrencies: const ['CNY'],
        today: today,
        amountInput: amountInput,
      );

  test('known person-paid expense is ready without adding payer role', () {
    final value = draft(payer: 'p2');
    expect(check(value), isEmpty);
    expect(value.personUuids, ['p1']);
    expect(value.payerPersonUuid, 'p2');
  });

  test('unknown and invalid payment modes block confirmation', () {
    expect(check(draft(paymentMode: 'UNKNOWN')), contains('paymentMode'));
    expect(check(draft(paymentMode: 'NEW_MODE')), contains('paymentMode'));
    expect(
      check(draft(paymentMode: 'PERSON_PAID', payer: null)),
      contains('payer'),
    );
  });

  test('explicit shared pool permits a null payer', () {
    expect(check(draft(paymentMode: 'SHARED_POOL', payer: null)), isEmpty);
    expect(
      check(draft(paymentMode: 'SHARED_POOL', payer: 'p1')),
      contains('paymentMode'),
    );
  });

  test(
    'blocks unsupported split, unknown participants and unresolved issues',
    () {
      expect(check(draft(splitMode: 'UNSUPPORTED')), contains('splitMode'));
      expect(
        check(draft(participantScope: 'UNKNOWN')),
        contains('participants'),
      );
      expect(
        check(
          draft(
            issues: const [
              AiDraftIssue(
                id: 'payer:x',
                field: 'payer',
                code: 'PERSON_AMBIGUOUS',
              ),
            ],
          ),
        ),
        contains('payer'),
      );
    },
  );

  test('blocks stale people, invalid category, date and amount', () {
    final stale = draft().copyWith(personUuids: const ['deleted']);
    expect(check(stale), contains('participants'));
    expect(
      check(draft().copyWith(categorySuggestion: 'removed')),
      contains('category'),
    );
    expect(
      check(draft(happenedAt: DateTime(2026, 10, 6))),
      contains('happenedAt'),
    );
    expect(check(draft().copyWith(happenedAt: null)), contains('happenedAt'));
    expect(check(draft(), amountInput: 'not money'), contains('amount'));
  });

  test(
    'v1 saved dates remain compatible while empty legacy payer is blocked',
    () {
      expect(check(draft(schemaVersion: 1, happenedAt: null)), isEmpty);
      expect(
        check(draft(schemaVersion: 1, paymentMode: 'UNKNOWN', payer: null)),
        contains('paymentMode'),
      );
    },
  );

  test('amount precision is checked for both edits and final draft values', () {
    for (final value in ['400.123', '0.001', '1e3', 'Infinity', 'NaN']) {
      expect(
        check(draft(), amountInput: value),
        contains('amount'),
        reason: value,
      );
    }
    expect(check(draft().copyWith(amount: 400.123)), contains('amount'));
    for (final value in ['400.12', '27.', '.50']) {
      expect(check(draft(), amountInput: value), isEmpty, reason: value);
    }
  });
}
