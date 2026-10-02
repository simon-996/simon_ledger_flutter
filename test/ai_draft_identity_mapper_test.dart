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
