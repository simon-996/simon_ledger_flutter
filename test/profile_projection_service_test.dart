import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/services/profile_projection_service.dart';

void main() {
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
