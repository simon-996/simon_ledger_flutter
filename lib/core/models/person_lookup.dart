import 'person.dart';

Map<String, Person> peopleByUuid(Iterable<Person> people) {
  final lookup = <String, Person>{};
  for (final person in people) {
    lookup[person.uuid] = person;
  }
  for (final person in people) {
    final syncedRemoteUuid = person.syncedRemoteUuid;
    if (syncedRemoteUuid == null || syncedRemoteUuid.isEmpty) {
      continue;
    }
    lookup.putIfAbsent(syncedRemoteUuid, () => person);
  }
  for (final person in people) {
    final linkedUserUuid = person.linkedUserUuid;
    if (linkedUserUuid == null || linkedUserUuid.isEmpty) {
      continue;
    }
    lookup.putIfAbsent(linkedUserUuid, () => person);
  }
  return lookup;
}

Person personOrFallback(
  Map<String, Person> peopleByUuid,
  String uuid, {
  String name = '未知',
  String avatar = '👤',
}) {
  return peopleByUuid[uuid] ??
      (Person()
        ..uuid = uuid
        ..name = name
        ..avatar = avatar);
}

String avatarsForPeople(
  Map<String, Person> peopleByUuid,
  Iterable<String> uuids, {
  String fallbackAvatar = '?',
}) {
  return uuids
      .map((uuid) => peopleByUuid[uuid]?.avatar ?? fallbackAvatar)
      .join();
}
