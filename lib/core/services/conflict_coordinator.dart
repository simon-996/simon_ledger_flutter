import '../models/conflict_record.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'conflict_snapshot_codec.dart';
import 'conflict_store.dart';
import 'sync_identity_resolver.dart';

enum ConflictResolutionOutcome { resolved, queued, requiresReview, failed }

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
    if (record.entityType == ConflictEntityType.profile &&
        record.operation != ConflictOperation.update) {
      throw StateError('个人资料不支持删除或恢复冲突');
    }

    final remoteLedgerUuid = await _remoteLedgerUuid(record);
    final path = _requestPath(record, remoteLedgerUuid);
    final data = await _requestData(record, version);
    final idempotencyKey =
        'resolve-${record.id}-${record.operation.name}-$version';
    ConflictMutationResult parse(Object? json) => _parseMutation(json, record);

    return switch (record.operation) {
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

  String _requestPath(ConflictRecord record, String? remoteLedgerUuid) {
    final String basePath;
    switch (record.entityType) {
      case ConflictEntityType.profile:
        return '/api/auth/me';
      case ConflictEntityType.ledger:
        basePath = '/api/ledgers/${record.remoteUuid}';
      case ConflictEntityType.member:
        basePath =
            '/api/ledgers/$remoteLedgerUuid/members/${record.remoteUuid}';
      case ConflictEntityType.person:
        basePath = '/api/ledgers/$remoteLedgerUuid/people/${record.remoteUuid}';
      case ConflictEntityType.transaction:
        basePath =
            '/api/ledgers/$remoteLedgerUuid/transactions/${record.remoteUuid}';
    }

    if (record.operation == ConflictOperation.restore) {
      return '$basePath/restore';
    }
    if (record.entityType == ConflictEntityType.member &&
        record.operation == ConflictOperation.update) {
      return '$basePath/role';
    }
    return basePath;
  }

  ConflictMutationResult _parseMutation(Object? json, ConflictRecord record) {
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
          snapshot['deleted'] == true ||
          record.operation == ConflictOperation.delete,
      snapshot: snapshot,
    );
  }
}

class ConflictCoordinator {
  ConflictCoordinator({
    required ConflictStore store,
    required ConflictSnapshotCodec codec,
    required ConflictResolutionGateway gateway,
  }) : _store = store,
       _codec = codec,
       _gateway = gateway;

  final ConflictStore _store;
  final ConflictSnapshotCodec _codec;
  final ConflictResolutionGateway _gateway;

  Future<bool> capture({
    required ApiException error,
    required ConflictOperation operation,
    String? ledgerUuid,
    required String localUuid,
    required Map<String, Object?> localSnapshot,
  }) async {
    final payload = error.conflict;
    if (!error.isConflict || payload == null) return false;

    await _store.upsert(
      ConflictRecord(
        id: _newId(payload),
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
    final record = await _store.findById(id);
    if (record == null) return;
    await _store.updateState(id, ConflictState.resolving);
    try {
      await _codec.applyRemote(record);
      await _store.remove(id);
    } catch (error) {
      await _store.updateState(
        id,
        ConflictState.failed,
        error: _message(error),
      );
      rethrow;
    }
  }

  Future<ConflictResolutionOutcome> keepLocal(String id) async {
    final record = await _store.findById(id);
    if (record == null) return ConflictResolutionOutcome.failed;
    if (record.remoteVersion == null) {
      await _store.updateState(
        id,
        ConflictState.failed,
        error: '云端版本不可用，请刷新后重试',
      );
      return ConflictResolutionOutcome.failed;
    }

    await _store.updateState(id, ConflictState.resolving);
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
      await _store.remove(id);
      return ConflictResolutionOutcome.resolved;
    } catch (error) {
      if (error is ApiException && error.isConflict) {
        await _refreshConflict(record, error);
        return ConflictResolutionOutcome.requiresReview;
      }
      if (_isNetworkFailure(error)) {
        await _store.updateState(
          id,
          ConflictState.queuedLocal,
          error: '网络不可用，将在联网后重试',
        );
        return ConflictResolutionOutcome.queued;
      }
      await _store.updateState(
        id,
        ConflictState.failed,
        error: _message(error),
      );
      return ConflictResolutionOutcome.failed;
    }
  }

  Future<void> retryQueuedLocal() async {
    final records = await _store.readAll();
    for (final record in records) {
      if (record.state == ConflictState.queuedLocal) {
        await keepLocal(record.id);
      }
    }
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
}
