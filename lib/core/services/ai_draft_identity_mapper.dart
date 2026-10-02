import '../models/ai_draft.dart';
import '../models/person.dart';

/// Resolve only against the active people of the current ledger/account.
/// Unknown or conflicting aliases stay unresolved instead of choosing a person.
AiDraft normalizeAiDraftPeople(AiDraft draft, Iterable<Person> people) {
  final aliases = <String, Set<String>>{};
  for (final person in people.where((person) => !person.isDeleted)) {
    for (final id in {person.uuid, person.remoteSyncUuid}) {
      aliases.putIfAbsent(id, () => <String>{}).add(person.uuid);
    }
  }
  String resolve(String id) {
    final matches = aliases[id];
    return matches?.length == 1 ? matches!.single : id;
  }

  return AiDraft(
    sourceText: draft.sourceText,
    type: draft.type,
    amount: draft.amount,
    currencyCode: draft.currencyCode,
    categorySuggestion: draft.categorySuggestion,
    note: draft.note,
    happenedAt: draft.happenedAt,
    payerPersonUuid: draft.payerPersonUuid == null
        ? null
        : resolve(draft.payerPersonUuid!),
    personUuids: draft.personUuids.map(resolve).toSet().toList(),
    unresolvedNames: draft.unresolvedNames,
    paymentMode: draft.effectivePaymentMode,
    personMatches: draft.personMatches
        .map(
          (match) => AiPersonMatch(
            sourceName: match.sourceName,
            role: match.role,
            personUuid: match.personUuid == null
                ? null
                : resolve(match.personUuid!),
            matchedName: match.matchedName,
            approximate: match.approximate,
            candidatePersonUuids: match.candidatePersonUuids
                .map(resolve)
                .toSet()
                .toList(),
          ),
        )
        .toList(),
  );
}
