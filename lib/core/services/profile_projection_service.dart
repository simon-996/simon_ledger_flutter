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
      final isSelf =
          person.uuid == 'self' ||
          person.uuid == 'p1' ||
          (linkedUserUuid != null && person.linkedUserUuid == linkedUserUuid) ||
          (person.name.trim() == previousName &&
              person.avatar.trim() == previousAvatar);
      if (!isSelf) continue;

      matched = true;
      person
        ..name = current.normalizedNickname
        ..avatar = current.personAvatar
        ..linkedUserUuid = linkedUserUuid ?? person.linkedUserUuid;
      await _database.savePerson(person);
    }

    if (!matched) {
      await _database.savePerson(
        Person()
          ..uuid = 'self'
          ..name = current.normalizedNickname
          ..avatar = current.personAvatar
          ..linkedUserUuid = linkedUserUuid,
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
      if (ledger.members.isEmpty) continue;

      var changed = false;
      final updatedMembers = ledger.members.map((member) {
        final matchesLinkedUser =
            linkedUserUuid != null &&
            linkedUserUuid.isNotEmpty &&
            member.userUuid == linkedUserUuid;
        final matchesPreviousProfile =
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
