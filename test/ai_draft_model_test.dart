import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';

void main() {
  test('old empty payer stays unknown and semantic data round-trips', () {
    final legacy = AiDraft.fromJson({
      'sourceText': '住宿400',
      'type': 0,
      'amount': 400.0,
      'currencyCode': 'CNY',
      'categorySuggestion': '居住',
      'payerPersonUuid': null,
      'personUuids': ['p-zhang'],
      'unresolvedNames': [],
    });
    expect(legacy.schemaVersion, 1);
    expect(legacy.paymentMode, 'UNKNOWN');

    const issue = AiDraftIssue(
      id: 'payer:PERSON_AMBIGUOUS:张三',
      field: 'payer',
      code: 'PERSON_AMBIGUOUS',
      sourceText: '张三',
      candidateUuids: ['p1', 'p2'],
    );
    final semantic = legacy.copyWith(
      schemaVersion: 2,
      paymentMode: 'PERSON_PAID',
      participantScope: 'ALL',
      splitMode: 'EQUAL',
      datePrecision: 'DAY',
      categoryOriginalSuggestion: '住宿',
      referenceDate: '2026-10-05',
      referenceZone: 'Asia/Shanghai',
      fieldSources: const {'splitMode': 'DEFAULT'},
      issues: const [issue],
      payerPersonUuid: 'p-zhang',
      happenedAt: DateTime(2026, 10, 4),
    );
    final restored = AiDraft.fromJson(semantic.toJson());
    expect(restored.schemaVersion, 2);
    expect(restored.paymentMode, 'PERSON_PAID');
    expect(restored.participantScope, 'ALL');
    expect(restored.categoryOriginalSuggestion, '住宿');
    expect(restored.referenceDate, '2026-10-05');
    expect(restored.fieldSources, {'splitMode': 'DEFAULT'});
    expect(restored.issues.single.candidateUuids, ['p1', 'p2']);

    final cleared = restored.copyWith(
      payerPersonUuid: null,
      happenedAt: null,
      note: null,
      categorySuggestion: null,
      categoryOriginalSuggestion: null,
      referenceDate: null,
      referenceZone: null,
    );
    expect(cleared.payerPersonUuid, isNull);
    expect(cleared.happenedAt, isNull);
    expect(cleared.note, isNull);
    expect(cleared.categorySuggestion, isNull);
    expect(cleared.categoryOriginalSuggestion, isNull);
    expect(cleared.referenceDate, isNull);
    expect(cleared.referenceZone, isNull);
    expect(cleared.issues.single.id, issue.id);
    expect(cleared.fieldSources, {'splitMode': 'DEFAULT'});
  });

  test('unknown server enums degrade to review-required values', () {
    final draft = AiDraft.fromJson({
      'schemaVersion': 2,
      'sourceText': '住宿400',
      'type': 0,
      'amount': 400,
      'currencyCode': 'CNY',
      'paymentMode': 'NEW_PROVIDER_MODE',
      'participantScope': 'EVERYONE',
      'splitMode': 'CUSTOM_RULE',
      'personUuids': ['p1'],
      'unresolvedNames': [],
      'issues': [],
    });
    expect(draft.paymentMode, 'UNKNOWN');
    expect(draft.participantScope, 'UNKNOWN');
    expect(draft.splitMode, 'UNKNOWN');
    expect(
      draft.issues.map((issue) => issue.field),
      containsAll(['paymentMode', 'participantScope', 'splitMode']),
    );
  });
}
