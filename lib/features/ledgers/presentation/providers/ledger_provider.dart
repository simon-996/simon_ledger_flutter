import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/repositories/ledger_repository.dart';

part 'ledger_provider.g.dart';

@riverpod
class LedgerNotifier extends _$LedgerNotifier {
  @override
  Future<List<Ledger>> build() async {
    await ref.watch(authTokenProvider.future);
    final repository = ref.watch(ledgerRepositoryProvider);
    if (repository is! RemoteLedgerRepository) {
      return repository.getAllLedgers();
    }

    var disposed = false;
    ref.onDispose(() => disposed = true);
    unawaited(_refreshRemote(repository, isDisposed: () => disposed));
    return repository.getCachedLedgers();
  }

  Future<void> _refreshRemote(
    RemoteLedgerRepository repository, {
    required bool Function() isDisposed,
  }) async {
    final ledgers = await repository.getAllLedgers();
    if (isDisposed()) return;
    state = AsyncValue.data(ledgers);
  }

  Future<void> addLedger(Ledger ledger) async {
    final repository = ref.read(ledgerRepositoryProvider);
    // Give it the highest sort order (put at the end)
    final currentLedgers = state.valueOrNull ?? [];
    if (currentLedgers.isNotEmpty) {
      ledger.sortOrder = currentLedgers.last.sortOrder + 1;
    }
    await repository.saveLedger(ledger);
    state = AsyncValue.data(_upsertLedger(currentLedgers, ledger));
  }

  Future<void> addLedgerWithPeople(Ledger ledger, List<Person> people) async {
    final repository = ref.read(ledgerRepositoryProvider);
    final currentLedgers = state.valueOrNull ?? [];
    if (currentLedgers.isNotEmpty) {
      ledger.sortOrder = currentLedgers.last.sortOrder + 1;
    }
    final created = await repository.createLedgerWithPeople(ledger, people);
    state = AsyncValue.data(_upsertLedger(currentLedgers, created.ledger));
  }

  Future<void> updateLedger(Ledger ledger) async {
    final repository = ref.read(ledgerRepositoryProvider);
    final currentLedgers = state.valueOrNull ?? [];
    await repository.saveLedger(ledger);
    state = AsyncValue.data(_upsertLedger(currentLedgers, ledger));
  }

  Future<void> reorderLedgers(int oldIndex, int newIndex) async {
    final currentLedgers = state.valueOrNull;
    if (currentLedgers == null) return;

    final items = List<Ledger>.from(currentLedgers);

    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    // Update sortOrder for all items
    for (int i = 0; i < items.length; i++) {
      items[i].sortOrder = i;
    }

    // Optimistically update the UI state
    state = AsyncValue.data(items);

    // Persist changes to database
    final repository = ref.read(ledgerRepositoryProvider);
    for (final ledger in items) {
      await repository.saveLedger(ledger);
    }
  }

  Future<void> deleteLedger(String uuid) async {
    final repository = ref.read(ledgerRepositoryProvider);
    final previousLedgers = state.valueOrNull;
    if (previousLedgers != null) {
      state = AsyncValue.data(
        previousLedgers.where((ledger) => ledger.uuid != uuid).toList(),
      );
    }

    try {
      await repository.deleteLedger(uuid);
    } catch (_) {
      if (previousLedgers != null) {
        state = AsyncValue.data(previousLedgers);
      }
      rethrow;
    }
  }

  List<Ledger> _upsertLedger(List<Ledger> ledgers, Ledger ledger) {
    final items = List<Ledger>.from(ledgers);
    final index = items.indexWhere((item) => item.uuid == ledger.uuid);
    if (index == -1) {
      items.add(ledger);
    } else {
      items[index] = ledger;
    }
    items.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return items;
  }
}
