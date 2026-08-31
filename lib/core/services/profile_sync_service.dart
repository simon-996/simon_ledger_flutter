import 'dart:async';

import '../config/avatar_config.dart';
import '../database/database_service.dart';
import '../models/local_profile.dart';
import '../models/conflict_record.dart';
import '../network/api_exception.dart';
import '../network/token_store.dart';
import '../preferences/local_profile_store.dart';
import '../repositories/auth_repository.dart';
import 'conflict_coordinator.dart';
import 'conflict_snapshot_codec.dart';
import 'profile_projection_service.dart';

enum ProfileSyncStatus { localOnly, queued, synced, skipped, stale, conflict }

class ProfileSyncResult {
  const ProfileSyncResult({required this.status, this.error});

  final ProfileSyncStatus status;
  final Object? error;
}

class ProfileSyncService {
  ProfileSyncService({
    required LocalProfileStore localProfileStore,
    required TokenStore tokenStore,
    required AuthRepository authRepository,
    required DatabaseService database,
    ConflictCoordinator? conflictCoordinator,
    ConflictSnapshotCodec? conflictCodec,
    ProfileProjectionService? profileProjection,
  }) : _localProfileStore = localProfileStore,
       _tokenStore = tokenStore,
       _authRepository = authRepository,
       _conflictCoordinator = conflictCoordinator,
       _conflictCodec = conflictCodec,
       _profileProjection =
           profileProjection ?? ProfileProjectionService(database);

  final LocalProfileStore _localProfileStore;
  final TokenStore _tokenStore;
  final AuthRepository _authRepository;
  final ConflictCoordinator? _conflictCoordinator;
  final ConflictSnapshotCodec? _conflictCodec;
  final ProfileProjectionService _profileProjection;
  Future<ProfileSyncResult>? _runningSync;

  Future<ProfileSyncResult> saveProfile(
    LocalProfile profile, {
    FutureOr<void> Function()? onLocalSaved,
  }) async {
    final previous = await _localProfileStore.read();
    final token = await _tokenStore.read();
    final canSync = token != null && token.isValid;
    final linkedUserUuid = canSync ? await _tokenStore.readAccountUuid() : null;
    final operationId = canSync ? _operationId() : null;
    final localProfile = profile.copyWith(
      pendingSync: canSync,
      pendingOperationId: operationId,
      syncError: null,
      updatedAt: DateTime.now(),
    );

    await _localProfileStore.save(localProfile);
    await _profileProjection.apply(
      previous: previous,
      current: localProfile,
      linkedUserUuid: linkedUserUuid,
    );
    await onLocalSaved?.call();

    if (!canSync) {
      return const ProfileSyncResult(status: ProfileSyncStatus.localOnly);
    }

    return _syncLatestAfterDebounce(operationId);
  }

  Future<ProfileSyncResult> syncPendingProfile({
    String? expectedOperationId,
  }) async {
    final runningSync = _runningSync;
    if (runningSync != null) {
      await runningSync;
    }

    final sync = _syncPendingProfileNow(
      expectedOperationId: expectedOperationId,
    );
    _runningSync = sync;
    try {
      return await sync;
    } finally {
      if (identical(_runningSync, sync)) {
        _runningSync = null;
      }
    }
  }

  Future<ProfileSyncResult> _syncLatestAfterDebounce(
    String? expectedOperationId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (expectedOperationId != null) {
      final latest = await _localProfileStore.read();
      if (latest.pendingOperationId != expectedOperationId) {
        return const ProfileSyncResult(status: ProfileSyncStatus.stale);
      }
    }

    return syncPendingProfile(expectedOperationId: expectedOperationId);
  }

  Future<ProfileSyncResult> _syncPendingProfileNow({
    String? expectedOperationId,
  }) async {
    final token = await _tokenStore.read();
    if (token == null || !token.isValid) {
      return const ProfileSyncResult(status: ProfileSyncStatus.skipped);
    }

    final profile = await _localProfileStore.read();
    if (!profile.pendingSync) {
      return const ProfileSyncResult(status: ProfileSyncStatus.skipped);
    }
    if (expectedOperationId != null &&
        profile.pendingOperationId != expectedOperationId) {
      return const ProfileSyncResult(status: ProfileSyncStatus.stale);
    }

    try {
      final user = await _authRepository.updateProfile(
        nickname: profile.normalizedNickname,
        avatar: profile.personAvatar,
        version: profile.remoteVersion,
      );
      final latest = await _localProfileStore.read();
      if (!_isSamePendingOperation(latest, profile)) {
        return const ProfileSyncResult(status: ProfileSyncStatus.stale);
      }

      final synced = LocalProfile(
        nickname: user.nickname,
        avatarIcon: AvatarConfig.normalizeKey(
          user.avatar ?? profile.avatarIcon,
        ),
        pendingSync: false,
        updatedAt: DateTime.now(),
        remoteVersion: user.version,
      );
      await _localProfileStore.save(synced);
      await _profileProjection.apply(
        previous: profile,
        current: synced,
        linkedUserUuid: user.uuid,
      );
      return const ProfileSyncResult(status: ProfileSyncStatus.synced);
    } catch (error) {
      final latest = await _localProfileStore.read();
      if (!_isSamePendingOperation(latest, profile)) {
        return const ProfileSyncResult(status: ProfileSyncStatus.stale);
      }

      if (await _captureConflict(error, profile)) {
        await _localProfileStore.save(
          latest.copyWith(
            pendingSync: false,
            pendingOperationId: null,
            syncError: null,
          ),
        );
        return ProfileSyncResult(
          status: ProfileSyncStatus.conflict,
          error: error,
        );
      }

      final failed = latest.copyWith(
        pendingSync: true,
        syncError: error.toString(),
      );
      await _localProfileStore.save(failed);
      return ProfileSyncResult(status: ProfileSyncStatus.queued, error: error);
    }
  }

  Future<bool> _captureConflict(Object error, LocalProfile profile) async {
    final coordinator = _conflictCoordinator;
    final codec = _conflictCodec;
    if (coordinator == null ||
        codec == null ||
        error is! ApiException ||
        !error.isConflict) {
      return false;
    }
    final accountUuid =
        await _tokenStore.readAccountUuid() ?? error.conflict!.entityUuid;
    return coordinator.capture(
      error: error,
      operation: ConflictOperation.update,
      localUuid: accountUuid,
      localSnapshot: codec.profileSnapshot(profile, accountUuid: accountUuid),
    );
  }

  bool _isSamePendingOperation(LocalProfile latest, LocalProfile syncing) {
    if (!latest.pendingSync) {
      return false;
    }

    final operationId = syncing.pendingOperationId;
    if (operationId != null && operationId.isNotEmpty) {
      return latest.pendingOperationId == operationId;
    }

    return latest.normalizedNickname == syncing.normalizedNickname &&
        latest.avatarIcon == syncing.avatarIcon &&
        latest.updatedAt == syncing.updatedAt;
  }

  Future<void> applyRemoteProfile(AuthUser user) async {
    final current = await _localProfileStore.read();
    if (current.pendingSync) {
      return;
    }

    final remoteProfile = LocalProfile(
      nickname: user.nickname,
      avatarIcon: AvatarConfig.normalizeKey(user.avatar ?? current.avatarIcon),
      pendingSync: false,
      updatedAt: DateTime.now(),
      remoteVersion: user.version,
    );
    await _localProfileStore.save(remoteProfile);
    await _profileProjection.apply(
      previous: current,
      current: remoteProfile,
      linkedUserUuid: user.uuid,
    );
  }

  String _operationId() {
    return 'profile-${DateTime.now().microsecondsSinceEpoch}';
  }
}
