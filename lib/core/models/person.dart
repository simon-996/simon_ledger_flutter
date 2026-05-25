class Person {
  int id = 0;

  late String uuid; // Original string id

  late String name;

  String avatar = '🧑';

  String? linkedUserUuid;

  bool isDeleted = false; // Soft delete flag
}
