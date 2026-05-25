import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';

part 'ledger_provider.g.dart';

@riverpod
class LedgerNotifier extends _$LedgerNotifier {
  @override
  Future<List<Ledger>> build() async {
    await ref.watch(authTokenProvider.future);
    final repository = ref.watch(ledgerRepositoryProvider);
    return await repository.getAllLedgers();
  }

  Future<void> addLedger(Ledger ledger) async {
    final repository = ref.read(ledgerRepositoryProvider);
    // Give it the highest sort order (put at the end)
    final currentLedgers = state.valueOrNull ?? [];
    if (currentLedgers.isNotEmpty) {
      ledger.sortOrder = currentLedgers.last.sortOrder + 1;
    }
    await repository.saveLedger(ledger);
    // Refresh the state
    ref.invalidateSelf();
  }

  Future<void> updateLedger(Ledger ledger) async {
    final repository = ref.read(ledgerRepositoryProvider);
    await repository.saveLedger(ledger);
    // Refresh the state
    ref.invalidateSelf();
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
      ref.invalidateSelf();
    } catch (_) {
      if (previousLedgers != null) {
        state = AsyncValue.data(previousLedgers);
      }
      rethrow;
    }
  }
}
