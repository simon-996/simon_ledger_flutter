enum AiPaymentMode {
  unconfirmed('unconfirmed'),
  sharedWallet('shared_wallet'),
  person('person');

  const AiPaymentMode(this.wireValue);
  final String wireValue;

  static AiPaymentMode fromWire(String? value) => values.firstWhere(
    (mode) => mode.wireValue == value,
    orElse: () => unconfirmed,
  );
}

class AiPersonMatch {
  const AiPersonMatch({
    required this.sourceName,
    required this.role,
    this.personUuid,
    this.matchedName,
    this.approximate = false,
    this.candidatePersonUuids = const [],
  });

  final String sourceName;
  final String role;
  final String? personUuid;
  final String? matchedName;
  final bool approximate;
  final List<String> candidatePersonUuids;

  factory AiPersonMatch.fromJson(Map<String, dynamic> json) => AiPersonMatch(
    sourceName: json['sourceName'] as String,
    role: json['role'] as String,
    personUuid: json['personUuid'] as String?,
    matchedName: json['matchedName'] as String?,
    approximate: json['approximate'] == true,
    candidatePersonUuids: (json['candidatePersonUuids'] as List<dynamic>? ?? [])
        .cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'sourceName': sourceName,
    'role': role,
    'personUuid': personUuid,
    'matchedName': matchedName,
    'approximate': approximate,
    'candidatePersonUuids': candidatePersonUuids,
  };
}

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
    this.paymentMode,
    this.personMatches = const [],
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
  final AiPaymentMode? paymentMode;
  final List<AiPersonMatch> personMatches;

  AiPaymentMode get effectivePaymentMode =>
      paymentMode ??
      (payerPersonUuid?.isNotEmpty == true
          ? AiPaymentMode.person
          : AiPaymentMode.unconfirmed);

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
    paymentMode: json['paymentMode'] == null
        ? null
        : AiPaymentMode.fromWire(json['paymentMode'] as String),
    personMatches: (json['personMatches'] as List<dynamic>? ?? [])
        .map((value) => AiPersonMatch.fromJson(value as Map<String, dynamic>))
        .toList(),
    personUuids: (json['personUuids'] as List<dynamic>)
        .map((value) => value as String)
        .toList(),
    unresolvedNames: (json['unresolvedNames'] as List<dynamic>)
        .map((value) => value as String)
        .toList(),
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
    'paymentMode': effectivePaymentMode.wireValue,
    'personMatches': personMatches.map((match) => match.toJson()).toList(),
    'personUuids': personUuids,
    'unresolvedNames': unresolvedNames,
  };
}
