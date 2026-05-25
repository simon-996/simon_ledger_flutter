import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/person.dart';

part 'person_provider.g.dart';

@riverpod
class PersonNotifier extends _$PersonNotifier {
  @override
  Future<List<Person>> build({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) async {
    await ref.watch(authTokenProvider.future);
    final repository = ref.watch(personRepositoryProvider);
    return await repository.getAllPeople(
      includeDeleted: includeDeleted,
      ledgerUuid: ledgerUuid,
    );
  }

  Future<void> addOrUpdatePerson(Person person) async {
    final repository = ref.read(personRepositoryProvider);
    await repository.savePerson(person, ledgerUuid: ledgerUuid);
    // Invalidate both true and false variants of the provider
    // Since Riverpod caches parameters separately
    ref.invalidate(personNotifierProvider);
  }

  Future<void> deletePerson(String uuid) async {
    final repository = ref.read(personRepositoryProvider);
    await repository.deletePerson(uuid, ledgerUuid: ledgerUuid);
    // Invalidate both true and false variants
    ref.invalidate(personNotifierProvider);
  }
}
