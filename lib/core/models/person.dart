import 'package:isar/isar.dart';

part 'person.g.dart';

@collection
class Person {
  Id id = Isar.autoIncrement; // Isar id
  
  @Index(unique: true, replace: true)
  late String uuid; // Original string id

  late String name;
  
  String avatar = '🧑';
  
  bool isDeleted = false; // Soft delete flag
}