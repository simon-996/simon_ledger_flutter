class Person {
  int id = 0;

  late String uuid; // Original string id

  late String name;

  String avatar = '🧑';

  String? linkedUserUuid;

  String? syncedRemoteUuid;

  bool isDeleted = false; // Soft delete flag

  bool pendingSync = false;

  String? syncError;

  String? pendingLedgerUuid;

  bool get hasSyncedRemoteCopy =>
      syncedRemoteUuid != null && syncedRemoteUuid!.isNotEmpty;

  String get remoteSyncUuid => hasSyncedRemoteCopy ? syncedRemoteUuid! : uuid;
}
