enum ConflictEntityType { profile, ledger, member, person, transaction }

enum ConflictOperation { update, delete, restore }

enum ConflictState { unresolved, queuedLocal, resolving, failed }

extension ConflictEntityTypeParsing on ConflictEntityType {
  static ConflictEntityType parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return ConflictEntityType.values.firstWhere(
      (type) => type.name == normalized,
      orElse: () => throw const FormatException('未知冲突实体类型'),
    );
  }
}

class ApiConflictPayload {
  const ApiConflictPayload({
    required this.entityType,
    required this.entityUuid,
    required this.submittedVersion,
    required this.remoteVersion,
    required this.remoteDeleted,
    required this.remoteSnapshot,
  });

  final ConflictEntityType entityType;
  final String entityUuid;
  final int submittedVersion;
  final int? remoteVersion;
  final bool remoteDeleted;
  final Map<String, Object?> remoteSnapshot;

  factory ApiConflictPayload.fromJson(Object? json) {
    if (json is! Map<dynamic, dynamic>) {
      throw const FormatException('冲突响应格式不正确');
    }
    final map = json.cast<String, dynamic>();
    final entityUuid = map['entityUuid']?.toString().trim() ?? '';
    final submittedVersion = (map['submittedVersion'] as num?)?.toInt();
    if (entityUuid.isEmpty || submittedVersion == null) {
      throw const FormatException('冲突响应缺少实体标识或提交版本');
    }
    final snapshot = map['remoteSnapshot'];
    return ApiConflictPayload(
      entityType: ConflictEntityTypeParsing.parse(map['entityType']),
      entityUuid: entityUuid,
      submittedVersion: submittedVersion,
      remoteVersion: (map['remoteVersion'] as num?)?.toInt(),
      remoteDeleted: map['remoteDeleted'] == true,
      remoteSnapshot: snapshot is Map<dynamic, dynamic>
          ? snapshot.cast<String, Object?>()
          : const {},
    );
  }
}

class ConflictRecord {
  const ConflictRecord({
    required this.id,
    required this.entityType,
    required this.ledgerUuid,
    required this.localUuid,
    required this.remoteUuid,
    required this.operation,
    required this.baseVersion,
    required this.remoteVersion,
    required this.localSnapshot,
    required this.remoteSnapshot,
    required this.remoteDeleted,
    required this.detectedAt,
    this.state = ConflictState.unresolved,
    this.error,
  });

  final String id;
  final ConflictEntityType entityType;
  final String? ledgerUuid;
  final String localUuid;
  final String remoteUuid;
  final ConflictOperation operation;
  final int baseVersion;
  final int? remoteVersion;
  final Map<String, Object?> localSnapshot;
  final Map<String, Object?> remoteSnapshot;
  final bool remoteDeleted;
  final DateTime detectedAt;
  final ConflictState state;
  final String? error;

  ConflictRecord copyWith({
    String? id,
    ConflictEntityType? entityType,
    Object? ledgerUuid = _unset,
    String? localUuid,
    String? remoteUuid,
    ConflictOperation? operation,
    int? baseVersion,
    Object? remoteVersion = _unset,
    Map<String, Object?>? localSnapshot,
    Map<String, Object?>? remoteSnapshot,
    bool? remoteDeleted,
    DateTime? detectedAt,
    ConflictState? state,
    Object? error = _unset,
  }) {
    return ConflictRecord(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      ledgerUuid: identical(ledgerUuid, _unset)
          ? this.ledgerUuid
          : ledgerUuid as String?,
      localUuid: localUuid ?? this.localUuid,
      remoteUuid: remoteUuid ?? this.remoteUuid,
      operation: operation ?? this.operation,
      baseVersion: baseVersion ?? this.baseVersion,
      remoteVersion: identical(remoteVersion, _unset)
          ? this.remoteVersion
          : remoteVersion as int?,
      localSnapshot: localSnapshot ?? this.localSnapshot,
      remoteSnapshot: remoteSnapshot ?? this.remoteSnapshot,
      remoteDeleted: remoteDeleted ?? this.remoteDeleted,
      detectedAt: detectedAt ?? this.detectedAt,
      state: state ?? this.state,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'entityType': entityType.name,
      'ledgerUuid': ledgerUuid,
      'localUuid': localUuid,
      'remoteUuid': remoteUuid,
      'operation': operation.name,
      'baseVersion': baseVersion,
      'remoteVersion': remoteVersion,
      'localSnapshot': localSnapshot,
      'remoteSnapshot': remoteSnapshot,
      'remoteDeleted': remoteDeleted,
      'detectedAt': detectedAt.toIso8601String(),
      'state': state.name,
      'error': error,
    };
  }

  factory ConflictRecord.fromJson(Map<String, dynamic> json) {
    final detectedAt = DateTime.tryParse(json['detectedAt']?.toString() ?? '');
    final baseVersion = (json['baseVersion'] as num?)?.toInt();
    if (detectedAt == null || baseVersion == null) {
      throw const FormatException('冲突记录缺少时间或版本');
    }
    return ConflictRecord(
      id: _requiredText(json, 'id'),
      entityType: ConflictEntityTypeParsing.parse(json['entityType']),
      ledgerUuid: _optionalText(json['ledgerUuid']),
      localUuid: _requiredText(json, 'localUuid'),
      remoteUuid: _requiredText(json, 'remoteUuid'),
      operation: _parseEnum(
        ConflictOperation.values,
        json['operation'],
        '冲突操作',
      ),
      baseVersion: baseVersion,
      remoteVersion: (json['remoteVersion'] as num?)?.toInt(),
      localSnapshot: _snapshot(json['localSnapshot']),
      remoteSnapshot: _snapshot(json['remoteSnapshot']),
      remoteDeleted: json['remoteDeleted'] == true,
      detectedAt: detectedAt,
      state: _parseEnum(ConflictState.values, json['state'], '冲突状态'),
      error: _optionalText(json['error']),
    );
  }

  static Map<String, Object?> _snapshot(Object? value) {
    if (value is! Map<dynamic, dynamic>) {
      throw const FormatException('冲突快照格式不正确');
    }
    return value.cast<String, Object?>();
  }

  static String _requiredText(Map<String, dynamic> json, String key) {
    final value = _optionalText(json[key]);
    if (value == null) {
      throw FormatException('冲突记录缺少 $key');
    }
    return value;
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static T _parseEnum<T extends Enum>(
    List<T> values,
    Object? value,
    String label,
  ) {
    final normalized = value?.toString().trim();
    return values.firstWhere(
      (item) => item.name == normalized,
      orElse: () => throw FormatException('$label 不正确'),
    );
  }
}

const _unset = Object();
