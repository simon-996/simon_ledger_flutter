import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    });

    test('saves a normalized nickname and avatar icon', () async {
      const store = LocalProfileStore();

      await store.save(
        const LocalProfile(nickname: ' Simon ', avatarIcon: 'star'),
      );

      final profile = await store.read();
      expect(profile.nickname, 'Simon');
      expect(profile.avatarIcon, 'star');
      expect(profile.personAvatar, '⭐');
    });
  });
}
