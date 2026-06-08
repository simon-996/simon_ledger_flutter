import 'dart:async';

import '../config/avatar_config.dart';
import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/local_profile.dart';
import '../models/person.dart';
import '../network/token_store.dart';
import '../preferences/local_profile_store.dart';
import '../repositories/auth_repository.dart';

enum ProfileSyncStatus { localOnly, queued, synced, skipped, stale }

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
  }) : _localProfileStore = localProfileStore,
       _tokenStore = tokenStore,
       _authRepository = authRepository,
       _database = database;

  final LocalProfileStore _localProfileStore;
  final TokenStore _tokenStore;
  final AuthRepository _authRepository;
  final DatabaseService _database;
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
    await _updateLocalSelfPeople(
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
      );
      await _localProfileStore.save(synced);
      await _updateLocalSelfPeople(
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

      final failed = latest.copyWith(
        pendingSync: true,
        syncError: error.toString(),
      );
      await _localProfileStore.save(failed);
      return ProfileSyncResult(status: ProfileSyncStatus.queued, error: error);
    }
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
    );
    await _localProfileStore.save(remoteProfile);
    await _updateLocalSelfPeople(
      previous: current,
      current: remoteProfile,
      linkedUserUuid: user.uuid,
    );
  }

  Future<void> _updateLocalSelfPeople({
    required LocalProfile previous,
    required LocalProfile current,
    String? linkedUserUuid,
  }) async {
    final people = await _database.getAllPeople(includeDeleted: true);
    var changed = false;
    var matched = false;
    final previousName = previous.normalizedNickname;
    final previousAvatar = previous.personAvatar;

    for (final person in people) {
      if (person.isDeleted) {
        continue;
      }

      final isSelf =
          person.uuid == 'self' ||
          person.uuid == 'p1' ||
          (linkedUserUuid != null && person.linkedUserUuid == linkedUserUuid) ||
          (person.name.trim() == previousName &&
              person.avatar.trim() == previousAvatar);
      if (!isSelf) {
        continue;
      }

      matched = true;
      person
        ..name = current.normalizedNickname
        ..avatar = current.personAvatar
        ..linkedUserUuid = linkedUserUuid ?? person.linkedUserUuid;
      changed = true;
    }

    if (!matched) {
      people.add(
        Person()
          ..uuid = 'self'
          ..name = current.normalizedNickname
          ..avatar = current.personAvatar
          ..linkedUserUuid = linkedUserUuid,
      );
      changed = true;
    }

    if (changed) {
      for (final person in people) {
        await _database.savePerson(person);
      }
    }

    await _updateCachedSelfLedgerMembers(
      previous: previous,
      current: current,
      linkedUserUuid: linkedUserUuid,
    );
  }

  Future<void> _updateCachedSelfLedgerMembers({
    required LocalProfile previous,
    required LocalProfile current,
    String? linkedUserUuid,
  }) async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    final previousName = previous.normalizedNickname;
    final previousAvatar = previous.personAvatar;

    for (final ledger in ledgers) {
      if (ledger.members.isEmpty) {
        continue;
      }

      var changed = false;
      final updatedMembers = ledger.members.map((member) {
        final matchesLinkedUser =
            linkedUserUuid != null &&
            linkedUserUuid.isNotEmpty &&
            member.userUuid == linkedUserUuid;
        final matchesPreviousProfile =
            member.nickname?.trim() == previousName &&
            member.avatar?.trim() == previousAvatar;
        if (!matchesLinkedUser && !matchesPreviousProfile) {
          return member;
        }

        changed = true;
        return LedgerMemberSummary(
          uuid: member.uuid,
          userUuid: linkedUserUuid ?? member.userUuid,
          nickname: current.normalizedNickname,
          avatar: current.personAvatar,
          role: member.role,
        );
      }).toList();

      if (!changed) {
        continue;
      }

      await _database.saveLedger(ledger..members = updatedMembers);
    }
  }

  String _operationId() {
    return 'profile-${DateTime.now().microsecondsSinceEpoch}';
  }
}
