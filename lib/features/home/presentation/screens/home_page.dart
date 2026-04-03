import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/models/ledger.dart';
import '../../../transactions/presentation/widgets/bookkeeping_tab.dart';
import '../../../ledgers/presentation/widgets/ledger_list_tab.dart';
import '../../../ledgers/presentation/widgets/create_ledger_sheet.dart';
import '../../../ledgers/presentation/screens/ledger_dashboard_page.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';
import '../../../statistics/presentation/widgets/statistics_tab.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // 监听 Provider
    final ledgersAsyncValue = ref.watch(ledgerNotifierProvider);
    final ledgerStatsAsyncValue = ref.watch(ledgerStatsProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: _currentIndex == 0 ? null : AppBar(
        title: Text(
          _currentIndex == 1
              ? '账本'
              : '统计',
        ),
      ),
      body: SafeArea(
        top: _currentIndex == 0,
        child: ledgersAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('加载账本失败: $err')),
        data: (ledgers) {
          return IndexedStack(
            index: _currentIndex,
            children: [
              BookkeepingTab(ledgers: ledgers),
              ledgerStatsAsyncValue.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('加载统计失败: $err')),
                data: (stats) => LedgerListTab(
                  ledgers: ledgers,
                  ledgerStats: stats,
                  onTap: _openLedger,
                  onEdit: _editLedger,
                  onDelete: _deleteLedger,
                  onCreate: _openCreateLedger,
                ),
              ),
              StatisticsTab(ledgers: ledgers),
            ],
          );
        },
      )),
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _openCreateLedger,
              icon: const Icon(Icons.add),
              label: const Text('添加账本'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: '记账',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: '账本',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
        ],
      ),
    );
  }

  void _openCreateLedger() async {
    final result = await showModalBottomSheet<CreateLedgerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const CreateLedgerSheet(),
    );

    if (!mounted || result == null) return;

    final newLedger = Ledger()
      ..uuid = DateTime.now().microsecondsSinceEpoch.toString()
      ..name = result.name
      ..baseCurrencyCode = result.baseCurrencyCode
      ..exchangeRateToCNY = result.exchangeRateToCNY
      ..personUuids = result.personIds;

    // 直接通过 Provider 操作，不再依赖全局 dbService，且 UI 会自动更新
    await ref.read(ledgerNotifierProvider.notifier).addLedger(newLedger);
  }
  
  void _editLedger(Ledger ledger) async {
    final result = await showModalBottomSheet<CreateLedgerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => CreateLedgerSheet(existingLedger: ledger),
    );

    if (!mounted || result == null) return;

    ledger.name = result.name;
    ledger.baseCurrencyCode = result.baseCurrencyCode;
    ledger.exchangeRateToCNY = result.exchangeRateToCNY;
    ledger.personUuids = result.personIds;

    await ref.read(ledgerNotifierProvider.notifier).updateLedger(ledger);
  }
  
  void _deleteLedger(Ledger ledger) async {
    await ref.read(ledgerNotifierProvider.notifier).deleteLedger(ledger.uuid);
    
    final prefs = await SharedPreferences.getInstance();
    final lastUuid = prefs.getString('last_selected_ledger_uuid');
    if (lastUuid == ledger.uuid) {
      prefs.remove('last_selected_ledger_uuid');
    }
  }

  void _openLedger(Ledger ledger) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LedgerDashboardPage(ledger: ledger),
      ),
    );
  }
}
