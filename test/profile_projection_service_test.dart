import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/services/profile_projection_service.dart';

void main() {
  test(
    'account ownership does not identify manual or other-account people as self',
    () async {
      SharedPreferences.setMockInitialValues({});
      final account = DatabaseService(
        scope: LocalDataScope.account('account-a'),
      );
      await account.savePerson(
        Person()
          ..uuid = 'manual'
          ..name = 'Alice'
          ..localAccountUuid = 'account-a',
      );
      await account.savePerson(
        Person()
          ..uuid = 'other'
          ..name = 'Bob'
          ..localAccountUuid = 'account-a'
          ..linkedUserUuid = 'account-b',
      );
      await account.savePerson(
        Person()
          ..uuid = 'actual-self'
          ..name = 'Old Simon'
          ..localAccountUuid = 'account-a'
          ..linkedUserUuid = 'account-a',
      );
      await ProfileProjectionService(account).apply(
        previous: const LocalProfile(nickname: 'Old Simon', avatarIcon: 'face'),
        current: const LocalProfile(nickname: 'New Simon', avatarIcon: 'star'),
        linkedUserUuid: 'account-a',
      );
      final people = {for (final p in await account.getAllPeople()) p.uuid: p};
      expect(people['manual']!.name, 'Alice');
      expect(people['manual']!.linkedUserUuid, isNull);
      expect(people['other']!.name, 'Bob');
      expect(people['other']!.linkedUserUuid, 'account-b');
      expect(people['actual-self']!.name, 'New Simon');
    },
  );

  test(
    'guest profile updates self but preserves matching manual name and avatar',
    () async {
      SharedPreferences.setMockInitialValues({});
      final guest = DatabaseService();
      for (final id in ['self', 'manual']) {
        await guest.savePerson(
          Person()
            ..uuid = id
            ..name = 'Same'
            ..avatar = '🙂',
        );
      }
      await ProfileProjectionService(guest).apply(
        previous: const LocalProfile(nickname: 'Same', avatarIcon: 'face'),
        current: const LocalProfile(nickname: 'New', avatarIcon: 'star'),
      );
      final people = {for (final p in await guest.getAllPeople()) p.uuid: p};
      expect(people['self']!.name, 'New');
      expect(people['manual']!.name, 'Same');
      expect(people['manual']!.avatar, '🙂');
    },
  );

  test('does not rewrite a guest person by nickname or avatar', () async {
    SharedPreferences.setMockInitialValues({});
    final guest = DatabaseService(scope: const LocalDataScope.guest());
    final accountA = DatabaseService(
      scope: LocalDataScope.account('account-a'),
    );
    await guest.savePerson(
      Person()
        ..uuid = 'guest-person'
        ..name = '旧昵称'
        ..avatar = '🙂',
    );

    await ProfileProjectionService(accountA).apply(
      previous: const LocalProfile(nickname: '旧昵称', avatarIcon: 'face'),
      current: const LocalProfile(nickname: '账号 A', avatarIcon: 'star'),
      linkedUserUuid: 'account-a',
    );

    final guestPerson = (await guest.getAllPeople())
        .where((person) => person.uuid == 'guest-person')
        .single;
    expect(guestPerson.name, '旧昵称');
    expect(guestPerson.avatar, '🙂');

    final accountPerson = (await accountA.getAllPeople())
        .where((person) => person.localAccountUuid == 'account-a')
        .single;
    expect(accountPerson.name, '账号 A');
    expect(accountPerson.linkedUserUuid, 'account-a');
  });
}
