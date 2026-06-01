import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/person.dart';
import '../../../../core/repositories/person_repository.dart';

part 'person_provider.g.dart';

final cachedPeopleProvider = FutureProvider<List<Person>>((ref) {
  return ref.watch(databaseProvider).getAllPeople(includeDeleted: true);
});

@riverpod
class PersonNotifier extends _$PersonNotifier {
  @override
  Future<List<Person>> build({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) async {
    await ref.watch(authTokenProvider.future);
    final repository = ref.watch(personRepositoryProvider);
    if (repository is! RemotePersonRepository) {
      return repository.getAllPeople(
        includeDeleted: includeDeleted,
        ledgerUuid: ledgerUuid,
      );
    }

    var disposed = false;
    ref.onDispose(() => disposed = true);
    unawaited(_refreshRemote(repository, isDisposed: () => disposed));
    return repository.getCachedPeople(
      includeDeleted: includeDeleted,
      ledgerUuid: ledgerUuid,
    );
  }

  Future<void> _refreshRemote(
    RemotePersonRepository repository, {
    required bool Function() isDisposed,
  }) async {
    final people = await repository.getAllPeople(
      includeDeleted: includeDeleted,
      ledgerUuid: ledgerUuid,
    );
    if (isDisposed()) return;
    state = AsyncValue.data(people);
  }

  Future<void> addOrUpdatePerson(Person person) async {
    final repository = ref.read(personRepositoryProvider);
    await repository.savePerson(person, ledgerUuid: ledgerUuid);
    ref.invalidate(cachedPeopleProvider);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(_upsertPerson(current, person));
    }
  }

  Future<void> deletePerson(String uuid) async {
    final repository = ref.read(personRepositoryProvider);
    await repository.deletePerson(uuid, ledgerUuid: ledgerUuid);
    ref.invalidate(cachedPeopleProvider);
    final current = state.valueOrNull;
    if (current != null) {
      if (includeDeleted) {
        state = AsyncValue.data(
          current.map((person) {
            if (person.uuid != uuid) return person;
            return person..isDeleted = true;
          }).toList(),
        );
      } else {
        state = AsyncValue.data(
          current.where((person) => person.uuid != uuid).toList(),
        );
      }
    }
  }

  List<Person> _upsertPerson(List<Person> people, Person person) {
    final items = List<Person>.from(people);
    final index = items.indexWhere((item) => item.uuid == person.uuid);
    if (index == -1) {
      items.add(person);
    } else {
      items[index] = person;
    }
    return items;
  }
}
