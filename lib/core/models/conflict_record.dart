enum ConflictEntityType { profile, ledger, member, person, transaction }

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
