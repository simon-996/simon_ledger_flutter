import 'person.dart';

Map<String, Person> peopleByUuid(Iterable<Person> people) {
  return {for (final person in people) person.uuid: person};
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
