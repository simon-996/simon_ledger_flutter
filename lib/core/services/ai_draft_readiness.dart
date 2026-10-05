import '../models/ai_draft.dart';

String? aiDraftAmountError(double originalAmount, {String? amountInput}) {
  final input = amountInput?.trim() ?? originalAmount.toString();
  final amount = double.tryParse(input);
  if (amount == null || !amount.isFinite || amount <= 0) {
    return '请输入大于 0 的有效金额';
  }
  if (!RegExp(r'^(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$').hasMatch(input)) {
    return '金额最多保留 2 位小数，请使用普通数字';
  }
  return null;
}

List<String> aiDraftBlockingFields(
  AiDraft draft, {
  required Set<String> activePersonIds,
  required List<String> categories,
  required List<String> supportedCurrencies,
  required DateTime today,
  String? amountInput,
}) {
  final fields = <String>{};
  if (aiDraftAmountError(draft.amount, amountInput: amountInput) != null) {
    fields.add('amount');
  }
  if (draft.type != 0 && draft.type != 1) fields.add('type');
  if (!supportedCurrencies.contains(draft.currencyCode)) {
    fields.add('currencyCode');
  }
  if (!categories.contains(draft.categorySuggestion)) fields.add('category');
  if (draft.personUuids.isEmpty ||
      !activePersonIds.containsAll(draft.personUuids)) {
    fields.add('participants');
  }
  if (draft.schemaVersion >= 2 && draft.participantScope == 'UNKNOWN') {
    fields.add('participants');
  }
  if (draft.type == 0) {
    if (draft.paymentMode == 'UNKNOWN' ||
        !const [
          'PERSON_PAID',
          'SHARED_POOL',
          'UNKNOWN',
        ].contains(draft.paymentMode)) {
      fields.add('paymentMode');
    }
    if (draft.paymentMode == 'PERSON_PAID' &&
        !activePersonIds.contains(draft.payerPersonUuid)) {
      fields.add('payer');
    }
    if (draft.paymentMode == 'SHARED_POOL' && draft.payerPersonUuid != null) {
      fields.add('paymentMode');
    }
  }
  if (draft.splitMode != 'EQUAL') fields.add('splitMode');
  final date = draft.happenedAt;
  if (draft.schemaVersion >= 2 && date == null) fields.add('happenedAt');
  if (date != null &&
      DateTime(
        date.year,
        date.month,
        date.day,
      ).isAfter(DateTime(today.year, today.month, today.day))) {
    fields.add('happenedAt');
  }
  fields.addAll(draft.issues.map((issue) => issue.field));
  if (draft.unresolvedNames.isNotEmpty) fields.add('legacy');
  return fields.toList();
}
