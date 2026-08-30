import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/conflict_record.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/repositories/auth_repository.dart';
import 'package:simon_ledger_flutter/core/services/profile_sync_service.dart';
import 'package:simon_ledger_flutter/core/services/conflict_coordinator.dart';
import 'package:simon_ledger_flutter/core/services/conflict_snapshot_codec.dart';
import 'package:simon_ledger_flutter/core/services/conflict_store.dart';

void main() {
  test(
    'saving profile updates cached ledger member display immediately',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = LocalProfileStore();
      await store.save(const LocalProfile(nickname: '旧昵称', avatarIcon: 'face'));

      final database = DatabaseService();
      await database.savePerson(
        Person()
          ..uuid = 'self'
          ..name = '旧昵称'
          ..avatar = '🙂',
      );
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-1'
          ..name = '共享账本'
          ..baseCurrencyCode = 'CNY'
          ..memberCount = 2
          ..members = [
            LedgerMemberSummary(
              uuid: 'member-self',
              userUuid: 'user-1',
              nickname: '旧昵称',
              avatar: '🙂',
              role: 'owner',
            ),
            LedgerMemberSummary(
              uuid: 'member-other',
              userUuid: 'user-2',
              nickname: '朋友',
              avatar: '👤',
              role: 'editor',
            ),
          ],
      );
      final service = ProfileSyncService(
        localProfileStore: store,
        tokenStore: TokenStore(),
        authRepository: _FakeAuthRepository(),
        database: database,
      );

      final result = await service.saveProfile(
        const LocalProfile(nickname: '新昵称', avatarIcon: 'star'),
      );

      expect(result.status, ProfileSyncStatus.localOnly);
      final ledger = (await database.getAllLedgers()).single;
      expect(ledger.members.first.displayName, '新昵称');
      expect(ledger.members.first.displayAvatar, '⭐');
      expect(ledger.members.last.displayName, '朋友');
    },
  );

  test(
    'structured profile conflict leaves the edit for manual review',
    () async {
      SharedPreferences.setMockInitialValues({});
      const profileStore = LocalProfileStore();
      final tokenStore = TokenStore();
      await tokenStore.save(
        const AuthToken(name: 'Authorization', value: 'token'),
      );
      await tokenStore.saveAccountUuid('user-1');
      await profileStore.save(
        const LocalProfile(
          nickname: '本机昵称',
          avatarIcon: 'star',
          pendingSync: true,
          pendingOperationId: 'profile-op',
          remoteVersion: 2,
        ),
      );
      final database = DatabaseService();
      final conflictStore = ConflictStore();
      final codec = ConflictSnapshotCodec(
        database: database,
        profileStore: profileStore,
      );
      final coordinator = ConflictCoordinator(
        store: conflictStore,
        codec: codec,
        gateway: _UnusedGateway(),
      );
      final service = ProfileSyncService(
        localProfileStore: profileStore,
        tokenStore: tokenStore,
        authRepository: _FakeAuthRepository(_profileConflict()),
        database: database,
        conflictCoordinator: coordinator,
        conflictCodec: codec,
      );

      final result = await service.syncPendingProfile();

      expect(result.status, ProfileSyncStatus.conflict);
      final profile = await profileStore.read();
      expect(profile.pendingSync, isFalse);
      expect(profile.pendingOperationId, isNull);
      expect(profile.syncError, isNull);
      final conflict = (await conflictStore.readAll()).single;
      expect(conflict.entityType, ConflictEntityType.profile);
      expect(conflict.localSnapshot['nickname'], '本机昵称');
      expect(conflict.remoteVersion, 3);
    },
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository([this.updateError]);

  final Object? updateError;

  @override
  Future<AuthUser> register({
    String? email,
    String? phone,
    required String password,
    required String nickname,
    String? avatar,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthLoginResult> login({
    required String account,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> me() {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> updateProfile({
    required String nickname,
    String? avatar,
    required int version,
  }) {
    final error = updateError;
    if (error != null) throw error;
    return Future.value(
      AuthUser(
        uuid: 'user-1',
        nickname: nickname,
        avatar: avatar,
        version: version + 1,
      ),
    );
  }
}

ApiException _profileConflict() {
  return const ApiException(
    code: 409001,
    statusCode: 409,
    message: '资料已被修改',
    conflict: ApiConflictPayload(
      entityType: ConflictEntityType.profile,
      entityUuid: 'user-1',
      submittedVersion: 2,
      remoteVersion: 3,
      remoteDeleted: false,
      remoteSnapshot: {
        'uuid': 'user-1',
        'nickname': '云端昵称',
        'avatar': '🐶',
        'version': 3,
      },
    ),
  );
}

class _UnusedGateway implements ConflictResolutionGateway {
  @override
  Future<ConflictMutationResult> submit(ConflictRecord record) {
    throw UnimplementedError();
  }
}
