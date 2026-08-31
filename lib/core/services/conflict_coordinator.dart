import '../models/conflict_record.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../network/token_store.dart';
import 'conflict_snapshot_codec.dart';
import 'conflict_store.dart';
import 'sync_identity_resolver.dart';

enum ConflictResolutionOutcome { resolved, queued, requiresReview, failed }

class ConflictRetrySummary {
  const ConflictRetrySummary({
    this.attemptedCount = 0,
    this.resolvedCount = 0,
    this.requiresReviewCount = 0,
    this.queuedCount = 0,
    this.failedCount = 0,
    this.affectedEntityTypes = const {},
  });

  final int attemptedCount;
  final int resolvedCount;
  final int requiresReviewCount;
  final int queuedCount;
  final int failedCount;
  final Set<ConflictEntityType> affectedEntityTypes;

  bool get changed => attemptedCount > 0;
}

class ConflictMutationResult {
  const ConflictMutationResult({
    required this.version,
    required this.deleted,
    this.snapshot = const {},
  });

  final int version;
  final bool deleted;
  final Map<String, Object?> snapshot;
}

abstract interface class ConflictResolutionGateway {
  Future<ConflictMutationResult> submit(ConflictRecord record);
}

class ApiConflictResolutionGateway implements ConflictResolutionGateway {
  const ApiConflictResolutionGateway({
    required ApiClient apiClient,
    required ConflictSnapshotCodec codec,
    required SyncIdentityResolver identityResolver,
  }) : _apiClient = apiClient,
       _codec = codec,
       _identityResolver = identityResolver;

  final ApiClient _apiClient;
  final ConflictSnapshotCodec _codec;
  final SyncIdentityResolver _identityResolver;

  @override
  Future<ConflictMutationResult> submit(ConflictRecord record) async {
    final version = record.remoteVersion;
    if (version == null || version < 1) {
      throw StateError('云端记录缺少可提交版本');
    }
    final operation = _effectiveOperation(record);
    if (record.entityType == ConflictEntityType.profile &&
        operation != ConflictOperation.update) {
      throw StateError('个人资料不支持删除或恢复冲突');
    }

    final remoteLedgerUuid = await _remoteLedgerUuid(record);
    final path = _requestPath(record, remoteLedgerUuid, operation);
    final data = await _requestData(record, version);
    final idempotencyKey = 'resolve-${record.id}-${operation.name}-$version';
    ConflictMutationResult parse(Object? json) =>
        _parseMutation(json, operation);

    return switch (operation) {
      ConflictOperation.update => _apiClient.put<ConflictMutationResult>(
        path,
        data: data,
        idempotencyKey: idempotencyKey,
        fromJson: parse,
      ),
      ConflictOperation.delete => _apiClient.delete<ConflictMutationResult>(
        path,
        data: data,
        idempotencyKey: idempotencyKey,
        fromJson: parse,
      ),
      ConflictOperation.restore => _apiClient.post<ConflictMutationResult>(
        path,
        data: data,
        idempotencyKey: idempotencyKey,
        fromJson: parse,
      ),
    };
  }

  Future<Map<String, Object?>> _requestData(
    ConflictRecord record,
    int version,
  ) async {
    final data = Map<String, Object?>.from(_codec.requestData(record, version));
    if (record.entityType != ConflictEntityType.transaction ||
        record.operation == ConflictOperation.delete) {
      return data;
    }

    final payerPersonUuid = data['payerPersonUuid']?.toString();
    if (payerPersonUuid != null && payerPersonUuid.isNotEmpty) {
      data['payerPersonUuid'] = await _identityResolver.resolvePersonUuid(
        payerPersonUuid,
      );
    }
    final personUuids = data['personUuids'];
    if (personUuids is List<dynamic>) {
      data['personUuids'] = await _identityResolver.resolvePersonUuids(
        personUuids.map((value) => value.toString()),
      );
    }
    return data;
  }

  Future<String?> _remoteLedgerUuid(ConflictRecord record) async {
    if (record.entityType == ConflictEntityType.profile ||
        record.entityType == ConflictEntityType.ledger) {
      return null;
    }
    final ledgerUuid = record.ledgerUuid;
    if (ledgerUuid == null || ledgerUuid.isEmpty) {
      throw StateError('冲突记录缺少所属账本');
    }
    return _identityResolver.resolveLedgerUuid(ledgerUuid);
  }

  ConflictOperation _effectiveOperation(ConflictRecord record) {
    if (record.operation == ConflictOperation.delete) {
      return ConflictOperation.delete;
    }
    return record.operation == ConflictOperation.restore || record.remoteDeleted
        ? ConflictOperation.restore
        : ConflictOperation.update;
  }

  String _requestPath(
    ConflictRecord record,
    String? remoteLedgerUuid,
    ConflictOperation operation,
  ) {
    final String basePath;
    switch (record.entityType) {
      case ConflictEntityType.profile:
        return '/api/auth/me';
      case ConflictEntityType.ledger:
        basePath = '/api/ledgers/${record.remoteUuid}';
      case ConflictEntityType.member:
        if (operation == ConflictOperation.delete &&
            record.localSnapshot['leaveLedger'] == true) {
          return '/api/ledgers/$remoteLedgerUuid/leave';
        }
        basePath =
            '/api/ledgers/$remoteLedgerUuid/members/${record.remoteUuid}';
      case ConflictEntityType.person:
        basePath = '/api/ledgers/$remoteLedgerUuid/people/${record.remoteUuid}';
      case ConflictEntityType.transaction:
        basePath =
            '/api/ledgers/$remoteLedgerUuid/transactions/${record.remoteUuid}';
    }

    if (operation == ConflictOperation.restore) {
      return '$basePath/restore';
    }
    if (record.entityType == ConflictEntityType.member &&
        operation == ConflictOperation.update) {
      return '$basePath/role';
    }
    return basePath;
  }

  ConflictMutationResult _parseMutation(
    Object? json,
    ConflictOperation operation,
  ) {
    if (json is! Map<dynamic, dynamic>) {
      throw const FormatException('冲突解决响应格式不正确');
    }
    final snapshot = json.cast<String, Object?>();
    final value = snapshot['version'];
    final version = value is num ? value.toInt() : int.tryParse('$value');
    if (version == null || version < 1) {
      throw const FormatException('冲突解决响应缺少版本');
    }
    return ConflictMutationResult(
      version: version,
      deleted:
          snapshot['deleted'] == true || operation == ConflictOperation.delete,
      snapshot: snapshot,
    );
  }
}

class ConflictCoordinator {
  ConflictCoordinator({
    required ConflictStore store,
    required ConflictSnapshotCodec codec,
    required ConflictResolutionGateway gateway,
    required TokenStore tokenStore,
  }) : _store = store,
       _codec = codec,
       _gateway = gateway,
       _tokenStore = tokenStore;

  final ConflictStore _store;
  final ConflictSnapshotCodec _codec;
  final ConflictResolutionGateway _gateway;
  final TokenStore _tokenStore;

  Future<bool> capture({
    required ApiException error,
    required ConflictOperation operation,
    String? ledgerUuid,
    required String localUuid,
    required Map<String, Object?> localSnapshot,
  }) async {
    final payload = error.conflict;
    if (!error.isConflict || payload == null) return false;
    final accountUuid = await _activeAccountUuid();
    if (accountUuid == null) return false;

    await _store.upsert(
      ConflictRecord(
        id: _newId(payload),
        accountUuid: accountUuid,
        entityType: payload.entityType,
        ledgerUuid: ledgerUuid,
        localUuid: localUuid,
        remoteUuid: payload.entityUuid,
        operation: operation,
        baseVersion: payload.submittedVersion,
        remoteVersion: payload.remoteVersion,
        localSnapshot: Map<String, Object?>.from(localSnapshot),
        remoteSnapshot: Map<String, Object?>.from(payload.remoteSnapshot),
        remoteDeleted: payload.remoteDeleted,
        detectedAt: DateTime.now(),
      ),
    );
    return true;
  }

  Future<void> useRemote(String id) async {
    final accountUuid = await _requireActiveAccountUuid();
    final record = await _store.findById(id, accountUuid: accountUuid);
    if (record == null) {
      throw StateError('当前账号无法处理这条冲突');
    }
    await _store.updateState(id, accountUuid, ConflictState.resolving);
    try {
      await _codec.applyRemote(record);
      await _store.remove(id, accountUuid: accountUuid);
    } catch (error) {
      await _store.updateState(
        id,
        accountUuid,
        ConflictState.failed,
        error: _message(error),
      );
      rethrow;
    }
  }

  Future<ConflictResolutionOutcome> keepLocal(String id) async {
    final accountUuid = await _requireActiveAccountUuid();
    final record = await _store.findById(id, accountUuid: accountUuid);
    if (record == null) {
      throw StateError('当前账号无法处理这条冲突');
    }
    if (record.operation == ConflictOperation.delete && record.remoteDeleted) {
      await _store.updateState(id, accountUuid, ConflictState.resolving);
      try {
        await _codec.applyRemote(record);
        await _store.remove(id, accountUuid: accountUuid);
        return ConflictResolutionOutcome.resolved;
      } catch (error) {
        await _store.updateState(
          id,
          accountUuid,
          ConflictState.failed,
          error: _message(error),
        );
        return ConflictResolutionOutcome.failed;
      }
    }
    if (record.remoteVersion == null) {
      await _store.updateState(
        id,
        accountUuid,
        ConflictState.failed,
        error: '云端版本不可用，请刷新后重试',
      );
      return ConflictResolutionOutcome.failed;
    }

    await _store.updateState(id, accountUuid, ConflictState.resolving);
    try {
      final result = await _gateway.submit(record);
      if (record.operation == ConflictOperation.delete ||
          result.snapshot.isEmpty) {
        await _codec.applyMutationVersion(record, result.version);
      } else {
        await _codec.applyRemote(
          record.copyWith(
            remoteVersion: result.version,
            remoteSnapshot: result.snapshot,
            remoteDeleted: result.deleted,
          ),
        );
      }
      await _store.remove(id, accountUuid: accountUuid);
      return ConflictResolutionOutcome.resolved;
    } catch (error) {
      if (error is ApiException && error.isConflict) {
        await _refreshConflict(record, error);
        return ConflictResolutionOutcome.requiresReview;
      }
      if (_isNetworkFailure(error)) {
        await _store.updateState(
          id,
          accountUuid,
          ConflictState.queuedLocal,
          error: '网络不可用，将在联网后重试',
        );
        return ConflictResolutionOutcome.queued;
      }
      await _store.updateState(
        id,
        accountUuid,
        ConflictState.failed,
        error: _message(error),
      );
      return ConflictResolutionOutcome.failed;
    }
  }

  Future<ConflictRetrySummary> retryQueuedLocal() async {
    final accountUuid = await _activeAccountUuid();
    if (accountUuid == null) return const ConflictRetrySummary();
    final records = await _store.readAll(accountUuid: accountUuid);
    var attemptedCount = 0;
    var resolvedCount = 0;
    var requiresReviewCount = 0;
    var queuedCount = 0;
    var failedCount = 0;
    final affectedEntityTypes = <ConflictEntityType>{};
    for (final record in records) {
      if (record.state != ConflictState.queuedLocal) continue;
      attemptedCount += 1;
      final outcome = await keepLocal(record.id);
      switch (outcome) {
        case ConflictResolutionOutcome.resolved:
          resolvedCount += 1;
          affectedEntityTypes.add(record.entityType);
        case ConflictResolutionOutcome.requiresReview:
          requiresReviewCount += 1;
        case ConflictResolutionOutcome.queued:
          queuedCount += 1;
        case ConflictResolutionOutcome.failed:
          failedCount += 1;
      }
    }
    return ConflictRetrySummary(
      attemptedCount: attemptedCount,
      resolvedCount: resolvedCount,
      requiresReviewCount: requiresReviewCount,
      queuedCount: queuedCount,
      failedCount: failedCount,
      affectedEntityTypes: Set.unmodifiable(affectedEntityTypes),
    );
  }

  Future<void> _refreshConflict(
    ConflictRecord current,
    ApiException error,
  ) async {
    final payload = error.conflict!;
    await _store.upsert(
      current.copyWith(
        entityType: payload.entityType,
        remoteUuid: payload.entityUuid,
        baseVersion: payload.submittedVersion,
        remoteVersion: payload.remoteVersion,
        remoteSnapshot: Map<String, Object?>.from(payload.remoteSnapshot),
        remoteDeleted: payload.remoteDeleted,
        state: ConflictState.unresolved,
        error: null,
      ),
    );
  }

  bool _isNetworkFailure(Object error) {
    return error is ApiException &&
        error.code == -1 &&
        error.statusCode == null;
  }

  static String _message(Object error) {
    if (error is ApiException) return error.message;
    return error.toString();
  }

  static String _newId(ApiConflictPayload payload) {
    return '${payload.entityType.name}-${payload.entityUuid}-'
        '${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<String?> _activeAccountUuid() async {
    final value = (await _tokenStore.readAccountUuid())?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String> _requireActiveAccountUuid() async {
    final accountUuid = await _activeAccountUuid();
    if (accountUuid == null) {
      throw StateError('请先登录后再处理冲突');
    }
    return accountUuid;
  }
}
