import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/person.dart';

part 'person_provider.g.dart';

@riverpod
class PersonNotifier extends _$PersonNotifier {
  @override
  Future<List<Person>> build({bool includeDeleted = false}) async {
    final db = ref.read(databaseProvider);
    return await db.getAllPeople(includeDeleted: includeDeleted);
  }

  Future<void> addOrUpdatePerson(Person person) async {
    final db = ref.read(databaseProvider);
    await db.savePerson(person);
    // Invalidate both true and false variants of the provider
    // Since Riverpod caches parameters separately
    ref.invalidate(personNotifierProvider);
  }

  Future<void> deletePerson(String uuid) async {
    final db = ref.read(databaseProvider);
    await db.deletePerson(uuid);
    // Invalidate both true and false variants
    ref.invalidate(personNotifierProvider);
  }
}
