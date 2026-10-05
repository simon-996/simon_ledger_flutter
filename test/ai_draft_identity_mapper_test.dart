import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_identity_mapper.dart';

void main() {
  final person = Person()
    ..uuid = 'local'
    ..syncedRemoteUuid = 'remote'
    ..name = '陈鑫';
  final draft = AiDraft(
    sourceText: '陈欣垫付',
    type: 0,
    amount: 30,
    currencyCode: 'CNY',
    personUuids: const ['remote', 'local'],
    payerPersonUuid: 'remote',
    unresolvedNames: const [],
    paymentMode: AiPaymentMode.person,
    personMatches: const [
      AiPersonMatch(
        sourceName: '陈欣',
        role: 'payer',
        personUuid: 'remote',
        matchedName: '陈鑫',
        approximate: true,
        candidatePersonUuids: ['remote'],
      ),
    ],
  );

  test('identity mapping includes role metadata and is idempotent', () {
    final local = normalizeAiDraftPeople(draft, [person]);
    expect(local.personUuids, ['local']);
    expect(local.payerPersonUuid, 'local');
    expect(local.personMatches.single.personUuid, 'local');
    expect(local.personMatches.single.candidatePersonUuids, ['local']);
    expect(normalizeAiDraftPeople(local, [person]).toJson(), local.toJson());
  });

  test(
    'v2 identity mapping retains semantic metadata and maps issue candidates',
    () {
      final semantic = draft.copyWith(
        schemaVersion: 2,
        participantScope: 'ALL',
        datePrecision: 'TIME',
        referenceDate: '2026-10-05',
        referenceZone: 'Asia/Shanghai',
        happenedAt: DateTime(2026, 10, 4, 14, 35),
        categoryOriginalSuggestion: '住宿',
        fieldSources: const {
          'participants': 'EXPLICIT',
          'splitMode': 'DEFAULT',
        },
        issues: const [
          AiDraftIssue(
            id: 'payer-ambiguous',
            field: 'payer',
            code: 'PERSON_AMBIGUOUS',
            sourceText: '陈欣',
            candidateUuids: ['remote'],
          ),
        ],
      );
      final local = normalizeAiDraftPeople(semantic, [person]);
      expect(local.schemaVersion, 2);
      expect(local.participantScope, 'ALL');
      expect(local.paymentMode, 'PERSON_PAID');
      expect(local.datePrecision, 'TIME');
      expect(local.happenedAt, semantic.happenedAt);
      expect(local.referenceDate, semantic.referenceDate);
      expect(local.referenceZone, semantic.referenceZone);
      expect(local.categoryOriginalSuggestion, '住宿');
      expect(local.fieldSources, semantic.fieldSources);
      expect(local.issues.single.candidateUuids, ['local']);
      expect(local.issues.single.id, 'payer-ambiguous');
      expect(normalizeAiDraftPeople(local, [person]).toJson(), local.toJson());
    },
  );

  test('people outside the supplied ledger or deleted remain unresolved', () {
    expect(normalizeAiDraftPeople(draft, []).payerPersonUuid, 'remote');
    final deleted = Person.copy(person)..isDeleted = true;
    expect(normalizeAiDraftPeople(draft, [deleted]).payerPersonUuid, 'remote');
  });

  test('conflicting remote aliases do not pick an arbitrary local person', () {
    final other = Person()
      ..uuid = 'different-local'
      ..syncedRemoteUuid = 'remote'
      ..name = '陈欣';
    expect(
      normalizeAiDraftPeople(draft, [person, other]).payerPersonUuid,
      'remote',
    );
  });
}
