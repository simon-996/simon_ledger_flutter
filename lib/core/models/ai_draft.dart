class AiDraft {
  const AiDraft({
    required this.sourceText,
    required this.type,
    required this.amount,
    required this.currencyCode,
    required this.personUuids,
    required this.unresolvedNames,
    this.categorySuggestion,
    this.note,
    this.happenedAt,
    this.payerPersonUuid,
  });

  final String? sourceText;
  final int type;
  final double amount;
  final String currencyCode;
  final String? categorySuggestion;
  final String? note;
  final DateTime? happenedAt;
  final String? payerPersonUuid;
  final List<String> personUuids;
  final List<String> unresolvedNames;

  factory AiDraft.fromJson(Map<String, dynamic> json) => AiDraft(
    sourceText: json['sourceText'] as String?,
    type: (json['type'] as num).toInt(),
    amount: (json['amount'] as num).toDouble(),
    currencyCode: json['currencyCode'] as String,
    categorySuggestion: json['categorySuggestion'] as String?,
    note: json['note'] as String?,
    happenedAt: json['happenedAt'] == null
        ? null
        : DateTime.parse(json['happenedAt'] as String),
    payerPersonUuid: json['payerPersonUuid'] as String?,
    personUuids: (json['personUuids'] as List<dynamic>)
        .map((value) => value as String).toList(),
    unresolvedNames: (json['unresolvedNames'] as List<dynamic>)
        .map((value) => value as String).toList(),
  );

  Map<String, dynamic> toJson() => {
    'sourceText': sourceText,
    'type': type,
    'amount': amount,
    'currencyCode': currencyCode,
    'categorySuggestion': categorySuggestion,
    'note': note,
    'happenedAt': happenedAt?.toIso8601String(),
    'payerPersonUuid': payerPersonUuid,
    'personUuids': personUuids,
    'unresolvedNames': unresolvedNames,
  };
}
