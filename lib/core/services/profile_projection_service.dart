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
    final previousName = previous.normalizedNickname;
    final previousAvatar = previous.personAvatar;

    for (final person in people) {
      if (person.isDeleted) continue;
      if (_database.scope.isAccount &&
          person.localAccountUuid != _database.scope.accountUuid) {
        continue;
      }

      final isAccountSelf =
          linkedUserUuid != null &&
          linkedUserUuid.isNotEmpty &&
          (person.localAccountUuid == linkedUserUuid ||
              person.linkedUserUuid == linkedUserUuid);
      final isGuestSelf =
          _database.scope.isGuest &&
          person.localAccountUuid == null &&
          (person.uuid == 'self' || person.uuid == 'p1');
      final isLegacyGuestSelf =
          _database.scope.isGuest &&
          linkedUserUuid == null &&
          person.localAccountUuid == null &&
          person.name.trim() == previousName &&
          person.avatar.trim() == previousAvatar;
      final isSelf = isAccountSelf || isGuestSelf || isLegacyGuestSelf;
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
    final previousName = previous.normalizedNickname;
    final previousAvatar = previous.personAvatar;

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
        final matchesPreviousProfile =
            _database.scope.isGuest &&
            linkedUserUuid == null &&
            member.nickname?.trim() == previousName &&
            member.avatar?.trim() == previousAvatar;
        if (!matchesLinkedUser && !matchesPreviousProfile) return member;

        changed = true;
        return LedgerMemberSummary(
          uuid: member.uuid,
          userUuid: linkedUserUuid ?? member.userUuid,
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
