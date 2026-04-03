import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';

part 'ledger_provider.g.dart';

@riverpod
class LedgerNotifier extends _$LedgerNotifier {
  @override
  Future<List<Ledger>> build() async {
    return _fetchLedgers();
  }

  Future<List<Ledger>> _fetchLedgers() async {
    final db = ref.read(databaseProvider);
    return await db.getAllLedgers();
  }

  Future<void> addLedger(Ledger ledger) async {
    final db = ref.read(databaseProvider);
    // Give it the highest sort order (put at the end)
    final currentLedgers = state.valueOrNull ?? [];
    if (currentLedgers.isNotEmpty) {
      ledger.sortOrder = currentLedgers.last.sortOrder + 1;
    }
    await db.saveLedger(ledger);
    // Refresh the state
    ref.invalidateSelf();
  }

  Future<void> updateLedger(Ledger ledger) async {
    final db = ref.read(databaseProvider);
    await db.saveLedger(ledger);
    // Refresh the state
    ref.invalidateSelf();
  }

  Future<void> reorderLedgers(int oldIndex, int newIndex) async {
    final currentLedgers = state.valueOrNull;
    if (currentLedgers == null) return;

    final items = List<Ledger>.from(currentLedgers);
    
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    // Update sortOrder for all items
    for (int i = 0; i < items.length; i++) {
      items[i].sortOrder = i;
    }

    // Optimistically update the UI state
    state = AsyncValue.data(items);

    // Persist changes to database
    final db = ref.read(databaseProvider);
    for (final ledger in items) {
      await db.saveLedger(ledger);
    }
  }

  Future<void> deleteLedger(String uuid) async {
    final db = ref.read(databaseProvider);
    await db.deleteLedger(uuid);
    // Refresh the state
    ref.invalidateSelf();
  }
}
