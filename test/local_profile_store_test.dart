import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';

void main() {
  group('LocalProfileStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns the default profile when no value is saved', () async {
      final profile = await const LocalProfileStore().read();

      expect(profile.nickname, '我');
      expect(profile.avatarIcon, 'person');
      expect(profile.remoteVersion, 1);
    });

    test('saves a normalized nickname and avatar icon', () async {
      const store = LocalProfileStore();

      await store.save(
        const LocalProfile(
          nickname: ' Simon ',
          avatarIcon: 'star',
          remoteVersion: 7,
        ),
      );

      final profile = await store.read();
      expect(profile.nickname, 'Simon');
      expect(profile.avatarIcon, 'star');
      expect(profile.personAvatar, '⭐');
      expect(profile.remoteVersion, 7);
    });

    test('keeps profiles isolated between guest and account scopes', () async {
      final guest = LocalProfileStore(scope: const LocalDataScope.guest());
      final accountA = LocalProfileStore(
        scope: LocalDataScope.account('account-a'),
      );
      final accountB = LocalProfileStore(
        scope: LocalDataScope.account('account-b'),
      );

      await guest.save(
        const LocalProfile(nickname: '游客', avatarIcon: 'person'),
      );
      await accountA.save(
        const LocalProfile(nickname: '账号 A', avatarIcon: 'person'),
      );

      expect((await guest.read()).nickname, '游客');
      expect((await accountA.read()).nickname, '账号 A');
      expect((await accountB.read()).nickname, '我');
    });
  });
}
