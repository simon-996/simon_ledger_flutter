class AiDraftIssue {
  const AiDraftIssue({
    required this.id,
    required this.field,
    required this.code,
    this.sourceText,
    this.candidateUuids = const [],
  });

  final String id;
  final String field;
  final String code;
  final String? sourceText;
  final List<String> candidateUuids;

  factory AiDraftIssue.fromJson(Map<String, dynamic> json) => AiDraftIssue(
    id: json['id'] as String? ?? 'unknown:UNSUPPORTED_ISSUE',
    field: json['field'] as String? ?? 'legacy',
    code: json['code'] as String? ?? 'UNSUPPORTED_ISSUE',
    sourceText: json['sourceText'] as String?,
    candidateUuids: (json['candidateUuids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'field': field,
    'code': code,
    'sourceText': sourceText,
    'candidateUuids': candidateUuids,
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
    this.schemaVersion = 1,
    this.paymentMode = 'UNKNOWN',
    this.participantScope = 'UNKNOWN',
    this.splitMode = 'EQUAL',
    this.datePrecision = 'DAY',
    this.categoryOriginalSuggestion,
    this.referenceDate,
    this.referenceZone,
    this.fieldSources = const {},
    this.issues = const [],
  });

  static const Object _unset = Object();

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
  final int schemaVersion;
  final String paymentMode;
  final String participantScope;
  final String splitMode;
  final String datePrecision;
  final String? categoryOriginalSuggestion;
  final String? referenceDate;
  final String? referenceZone;
  final Map<String, String> fieldSources;
  final List<AiDraftIssue> issues;

  factory AiDraft.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['schemaVersion'];
    final schemaVersion = rawVersion == null
        ? 1
        : rawVersion is num && rawVersion.toInt() == 1
        ? 1
        : 2;
    final payerPersonUuid = json['payerPersonUuid'] as String?;
    final issues = (json['issues'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AiDraftIssue.fromJson)
        .toList();

    String semanticValue(
      String field,
      Set<String> allowed, {
      required String fallback,
    }) {
      final raw = json[field];
      if (raw == null) return fallback;
      if (raw is String && allowed.contains(raw)) return raw;
      issues.add(
        AiDraftIssue(
          id: '$field:UNSUPPORTED_ENUM:${raw.toString()}',
          field: field,
          code: 'UNSUPPORTED_ENUM',
          sourceText: raw.toString(),
        ),
      );
      return fallback;
    }

    final paymentMode = semanticValue('paymentMode', const {
      'PERSON_PAID',
      'SHARED_POOL',
      'UNKNOWN',
    }, fallback: payerPersonUuid == null ? 'UNKNOWN' : 'PERSON_PAID');
    final participantScope = semanticValue('participantScope', const {
      'ALL',
      'SPECIFIED',
      'UNKNOWN',
    }, fallback: 'UNKNOWN');
    final splitMode = semanticValue('splitMode', const {
      'EQUAL',
      'UNSUPPORTED',
      'UNKNOWN',
    }, fallback: schemaVersion == 1 ? 'EQUAL' : 'UNKNOWN');
    final datePrecision = semanticValue('datePrecision', const {
      'DAY',
      'TIME',
    }, fallback: 'DAY');
    final rawFieldSources = json['fieldSources'];
    final fieldSources = <String, String>{};
    if (rawFieldSources is Map) {
      rawFieldSources.forEach((key, value) {
        if (key is String && value is String) fieldSources[key] = value;
      });
    }

    return AiDraft(
      sourceText: json['sourceText'] as String?,
      type: (json['type'] as num).toInt(),
      amount: (json['amount'] as num).toDouble(),
      currencyCode: json['currencyCode'] as String,
      categorySuggestion: json['categorySuggestion'] as String?,
      note: json['note'] as String?,
      happenedAt: json['happenedAt'] == null
          ? null
          : DateTime.parse(json['happenedAt'] as String),
      payerPersonUuid: payerPersonUuid,
      personUuids: (json['personUuids'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      unresolvedNames: (json['unresolvedNames'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      schemaVersion: schemaVersion,
      paymentMode: paymentMode,
      participantScope: participantScope,
      splitMode: splitMode,
      datePrecision: datePrecision,
      categoryOriginalSuggestion: json['categoryOriginalSuggestion'] as String?,
      referenceDate: json['referenceDate'] as String?,
      referenceZone: json['referenceZone'] as String?,
      fieldSources: fieldSources,
      issues: issues,
    );
  }

  AiDraft copyWith({
    Object? sourceText = _unset,
    int? type,
    double? amount,
    String? currencyCode,
    Object? categorySuggestion = _unset,
    Object? note = _unset,
    Object? happenedAt = _unset,
    Object? payerPersonUuid = _unset,
    List<String>? personUuids,
    List<String>? unresolvedNames,
    int? schemaVersion,
    String? paymentMode,
    String? participantScope,
    String? splitMode,
    String? datePrecision,
    Object? categoryOriginalSuggestion = _unset,
    Object? referenceDate = _unset,
    Object? referenceZone = _unset,
    Map<String, String>? fieldSources,
    List<AiDraftIssue>? issues,
  }) => AiDraft(
    sourceText: identical(sourceText, _unset)
        ? this.sourceText
        : sourceText as String?,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    currencyCode: currencyCode ?? this.currencyCode,
    categorySuggestion: identical(categorySuggestion, _unset)
        ? this.categorySuggestion
        : categorySuggestion as String?,
    note: identical(note, _unset) ? this.note : note as String?,
    happenedAt: identical(happenedAt, _unset)
        ? this.happenedAt
        : happenedAt as DateTime?,
    payerPersonUuid: identical(payerPersonUuid, _unset)
        ? this.payerPersonUuid
        : payerPersonUuid as String?,
    personUuids: personUuids ?? this.personUuids,
    unresolvedNames: unresolvedNames ?? this.unresolvedNames,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    paymentMode: paymentMode ?? this.paymentMode,
    participantScope: participantScope ?? this.participantScope,
    splitMode: splitMode ?? this.splitMode,
    datePrecision: datePrecision ?? this.datePrecision,
    categoryOriginalSuggestion: identical(categoryOriginalSuggestion, _unset)
        ? this.categoryOriginalSuggestion
        : categoryOriginalSuggestion as String?,
    referenceDate: identical(referenceDate, _unset)
        ? this.referenceDate
        : referenceDate as String?,
    referenceZone: identical(referenceZone, _unset)
        ? this.referenceZone
        : referenceZone as String?,
    fieldSources: fieldSources ?? this.fieldSources,
    issues: issues ?? this.issues,
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
    'schemaVersion': schemaVersion,
    'paymentMode': paymentMode,
    'participantScope': participantScope,
    'splitMode': splitMode,
    'datePrecision': datePrecision,
    'categoryOriginalSuggestion': categoryOriginalSuggestion,
    'referenceDate': referenceDate,
    'referenceZone': referenceZone,
    'fieldSources': fieldSources,
    'issues': issues.map((issue) => issue.toJson()).toList(),
  };
}
