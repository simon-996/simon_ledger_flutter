import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/repositories/auth_repository.dart';
import 'package:simon_ledger_flutter/core/services/profile_sync_service.dart';

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
}

class _FakeAuthRepository implements AuthRepository {
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
  Future<AuthUser> updateProfile({required String nickname, String? avatar}) {
    throw UnimplementedError();
  }
}
