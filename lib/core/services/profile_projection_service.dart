import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/local_profile.dart';
import '../models/person.dart';

class ProfileProjectionService {
  const ProfileProjectionService(this._database);

  final DatabaseService _database;

  Future<void> apply({
    required LocalProfile previous,
    required LocalProfile current,
    String? linkedUserUuid,
  }) async {
    await _updateLocalSelfPeople(
      previous: previous,
      current: current,
      linkedUserUuid: linkedUserUuid,
    );
    await _updateCachedSelfLedgerMembers(
      previous: previous,
      current: current,
      linkedUserUuid: linkedUserUuid,
    );
  }

  Future<void> _updateLocalSelfPeople({
    required LocalProfile previous,
    required LocalProfile current,
    String? linkedUserUuid,
  }) async {
    final people = await _database.getAllPeople(includeDeleted: true);
    var matched = false;

    for (final person in people) {
      if (person.isDeleted) continue;
      if (_database.scope.isAccount &&
          person.localAccountUuid != _database.scope.accountUuid) {
        continue;
      }

      final isAccountSelf =
          linkedUserUuid != null &&
          linkedUserUuid.isNotEmpty &&
          person.linkedUserUuid == linkedUserUuid;
      final isGuestSelf =
          _database.scope.isGuest &&
          person.localAccountUuid == null &&
          linkedUserUuid == null &&
          person.representsLocalSelf;
      final isSelf = isAccountSelf || isGuestSelf;
      if (!isSelf) continue;

      matched = true;
      person
        ..name = current.normalizedNickname
        ..avatar = current.personAvatar
        ..linkedUserUuid = linkedUserUuid ?? person.linkedUserUuid
        ..localAccountUuid = _database.scope.isAccount
            ? linkedUserUuid ?? person.localAccountUuid
            : null;
      await _database.savePerson(person);
    }

    if (!matched) {
      await _database.savePerson(
        Person()
          ..uuid = linkedUserUuid == null ? 'self' : 'self:$linkedUserUuid'
          ..isLocalSelf = true
          ..name = current.normalizedNickname
          ..avatar = current.personAvatar
          ..linkedUserUuid = linkedUserUuid
          ..localAccountUuid = _database.scope.isAccount
              ? linkedUserUuid
              : null,
      );
    }
  }

  Future<void> _updateCachedSelfLedgerMembers({
    required LocalProfile previous,
    required LocalProfile current,
    String? linkedUserUuid,
  }) async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);

    for (final ledger in ledgers) {
      if (_database.scope.isAccount &&
          ledger.localAccountUuid != _database.scope.accountUuid) {
        continue;
      }
      if (ledger.members.isEmpty) continue;

      var changed = false;
      final updatedMembers = ledger.members.map((member) {
        final matchesLinkedUser =
            linkedUserUuid != null &&
            linkedUserUuid.isNotEmpty &&
            member.userUuid == linkedUserUuid;
        if (!matchesLinkedUser) return member;

        changed = true;
        return LedgerMemberSummary(
          uuid: member.uuid,
          userUuid: linkedUserUuid,
          nickname: current.normalizedNickname,
          avatar: current.personAvatar,
          role: member.role,
          version: member.version,
        );
      }).toList();

      if (changed) {
        await _database.saveLedger(ledger..members = updatedMembers);
      }
    }
  }
}
