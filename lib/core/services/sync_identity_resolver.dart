import '../database/database_service.dart';
import '../models/ledger.dart';
import '../models/person.dart';

class SyncIdentityResolver {
  const SyncIdentityResolver(this._database);

  final DatabaseService _database;

  Future<String> resolveLedgerUuid(String uuid) async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    final ledger = ledgers.where((item) {
      return item.uuid == uuid || item.syncedRemoteUuid == uuid;
    }).firstOrNull;
    return ledger?.remoteSyncUuid ?? uuid;
  }

  Future<String> resolvePersonUuid(String uuid) async {
    final people = await _database.getAllPeople(includeDeleted: true);
    final person = people.where((item) {
      return item.uuid == uuid || item.syncedRemoteUuid == uuid;
    }).firstOrNull;
    return person?.remoteSyncUuid ?? uuid;
  }

  Future<List<String>> resolvePersonUuids(Iterable<String> uuids) async {
    final people = await _database.getAllPeople(includeDeleted: true);
    final remoteUuidByUuid = <String, String>{};
    for (final person in people) {
      remoteUuidByUuid[person.uuid] = person.remoteSyncUuid;
      final syncedRemoteUuid = person.syncedRemoteUuid;
      if (syncedRemoteUuid != null && syncedRemoteUuid.isNotEmpty) {
        remoteUuidByUuid[syncedRemoteUuid] = syncedRemoteUuid;
      }
    }
    return uuids.map((uuid) => remoteUuidByUuid[uuid] ?? uuid).toList();
  }

  Future<void> recordLedgerMapping({
    required String localUuid,
    required String remoteUuid,
  }) async {
    final ledger = await _findLedger(localUuid);
    if (ledger == null) return;
    await _database.saveLedger(
      ledger
        ..syncedRemoteUuid = remoteUuid
        ..cloudPolicy = LedgerCloudPolicy.cloudManaged,
    );
  }

  Future<void> recordPersonMapping({
    required String localUuid,
    required String remoteUuid,
  }) async {
    final person = await _findPerson(localUuid);
    if (person == null) return;
    await _database.savePerson(person..syncedRemoteUuid = remoteUuid);
  }

  Future<Ledger?> _findLedger(String uuid) async {
    final ledgers = await _database.getAllLedgers(includeDeleted: true);
    return ledgers.where((item) => item.uuid == uuid).firstOrNull;
  }

  Future<Person?> _findPerson(String uuid) async {
    final people = await _database.getAllPeople(includeDeleted: true);
    return people.where((item) => item.uuid == uuid).firstOrNull;
  }
}
