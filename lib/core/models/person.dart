class Person {
  Person();

  Person.copy(Person source)
    : id = source.id,
      version = source.version,
      uuid = source.uuid,
      name = source.name,
      avatar = source.avatar,
      isLocalSelf = source.representsLocalSelf,
      linkedUserUuid = source.linkedUserUuid,
      syncedRemoteUuid = source.syncedRemoteUuid,
      localAccountUuid = source.localAccountUuid,
      isDeleted = source.isDeleted,
      pendingSync = source.pendingSync,
      syncError = source.syncError,
      pendingLedgerUuid = source.pendingLedgerUuid;

  int id = 0;

  int version = 1;

  late String uuid; // Original string id

  late String name;

  String avatar = '🧑';

  // Provenance of the system-created local self, independent of display name.
  bool isLocalSelf = false;

  bool get representsLocalSelf =>
      isLocalSelf ||
      RegExp(r'^(?:guest:)?(?:self|p1|self-\d+)$').hasMatch(uuid);

  String? linkedUserUuid;

  String? syncedRemoteUuid;

  String? localAccountUuid;

  bool isDeleted = false; // Soft delete flag

  bool pendingSync = false;

  String? syncError;

  String? pendingLedgerUuid;

  bool get hasSyncedRemoteCopy =>
      syncedRemoteUuid != null && syncedRemoteUuid!.isNotEmpty;

  String get remoteSyncUuid => hasSyncedRemoteCopy ? syncedRemoteUuid! : uuid;
}
