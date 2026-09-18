import '../database/database_service.dart';
import '../models/invite_join_result.dart';
import '../models/ledger.dart';
import '../models/person.dart';

class InviteJoinCache {
  const InviteJoinCache(this._database);

  final DatabaseService _database;

  Future<void> apply(InviteJoinResult result, {String? accountUuid}) async {
    if (!result.isComplete) {
      await _database.restoreLedgerAccess(result.invite.ledgerUuid);
      return;
    }
    if (!result.isValid) {
      throw StateError('加入响应身份校验失败，请重试');
    }

    final remoteLedger = result.ledger!;
    final remotePerson = result.person!;
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    var ledger = ledgers.where((item) {
      return item.uuid == remoteLedger.uuid ||
          item.syncedRemoteUuid == remoteLedger.uuid;
    }).firstOrNull;
    ledger ??= Ledger()..uuid = remoteLedger.uuid;
    final ledgerHasPendingChanges = ledger.pendingSync;

    if (!ledgerHasPendingChanges) {
      ledger
        ..name = remoteLedger.name
        ..baseCurrencyCode = remoteLedger.baseCurrencyCode
        ..exchangeRateToCNY = remoteLedger.exchangeRateToCny
        ..version = remoteLedger.version;
    }
    ledger
      ..syncedRemoteUuid = remoteLedger.uuid
      ..cacheOwnerUserUuid = accountUuid
      ..cloudPolicy = LedgerCloudPolicy.cloudManaged
      ..role = remoteLedger.role
      ..memberCount = remoteLedger.memberCount
      ..members = remoteLedger.members
      ..isDeleted = false;
    if (!ledgerHasPendingChanges) {
      ledger
        ..pendingSync = false
        ..syncError = null;
    }

    final people = await _database.getAllPeople(includeDeleted: true);
    var person = people.where((item) {
      final isRemoteMatch =
          item.uuid == remotePerson.uuid ||
          item.syncedRemoteUuid == remotePerson.uuid;
      final isLinkedLedgerMatch =
          ledger!.personUuids.contains(item.uuid) &&
          item.linkedUserUuid == remotePerson.linkedUserUuid;
      return isRemoteMatch || isLinkedLedgerMatch;
    }).firstOrNull;
    person ??= Person()..uuid = remotePerson.uuid;
    final personHasPendingChanges = person.pendingSync;
    final localPersonUuid = person.uuid;
    if (!personHasPendingChanges) {
      person
        ..name = remotePerson.name
        ..avatar = remotePerson.avatar ?? '🧑'
        ..version = remotePerson.version;
    }
    person
      ..linkedUserUuid = remotePerson.linkedUserUuid
      ..syncedRemoteUuid = remotePerson.uuid
      ..isDeleted = false;
    if (!personHasPendingChanges) {
      person
        ..pendingSync = false
        ..syncError = null;
    }

    await _database.savePerson(person);
    ledger.personUuids = {
      ...ledger.personUuids.where(
        (uuid) => uuid != remotePerson.uuid && uuid != localPersonUuid,
      ),
      localPersonUuid,
    }.toList();
    await _database.saveLedger(ledger);
  }
}
