import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/preferences/last_selected_ledger_preference.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../auth/presentation/widgets/account_tab.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';
import '../../../ledgers/presentation/screens/ledger_dashboard_page.dart';
import '../../../ledgers/presentation/widgets/create_ledger_sheet.dart';
import '../../../ledgers/presentation/widgets/ledger_list_tab.dart';
import '../../../statistics/presentation/widgets/statistics_tab.dart';
import '../../../transactions/presentation/widgets/bookkeeping_tab.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final ledgersAsyncValue = ref.watch(ledgerNotifierProvider);
    final ledgerStatsAsyncValue = ref.watch(ledgerStatsProvider);
    final isAccountTab = _currentIndex == 3;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: _currentIndex == 0
          ? null
          : AppBar(title: Text(_appBarTitle), centerTitle: false),
      body: SafeArea(
        top: _currentIndex == 0,
        child: isAccountTab
            ? const AccountTab()
            : ledgersAsyncValue.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: '账本加载失败',
                  message: '$err',
                ),
                data: (ledgers) {
                  return AppAnimatedIndexedStack(
                    index: _currentIndex,
                    children: [
                      BookkeepingTab(ledgers: ledgers),
                      ledgerStatsAsyncValue.when(
                        loading: () => LedgerListTab(
                          ledgers: ledgers,
                          ledgerStats: const {},
                          onTap: _openLedger,
                          onEdit: _editLedger,
                          onDelete: _deleteLedger,
                          onCreate: _openCreateLedger,
                        ),
                        error: (err, stack) => LedgerListTab(
                          ledgers: ledgers,
                          ledgerStats: const {},
                          onTap: _openLedger,
                          onEdit: _editLedger,
                          onDelete: _deleteLedger,
                          onCreate: _openCreateLedger,
                        ),
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
              ),
      ),
      floatingActionButton: AnimatedSwitcher(
        duration: AppMotion.normal,
        switchInCurve: AppMotion.emphasized,
        switchOutCurve: AppMotion.standard,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: _currentIndex == 1
            ? FloatingActionButton.extended(
                key: const ValueKey('ledger-fab'),
                onPressed: _openCreateLedger,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建账本'),
              )
            : const SizedBox.shrink(key: ValueKey('empty-fab')),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          border: Border(
            top: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(Icons.edit_note_rounded),
              label: '记账',
            ),
            NavigationDestination(
              icon: Icon(Icons.book_outlined),
              selectedIcon: Icon(Icons.book_rounded),
              label: '账本',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: '统计',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle_rounded),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }

  String get _appBarTitle {
    return switch (_currentIndex) {
      1 => '账本',
      2 => '统计',
      3 => '我的',
      _ => '',
    };
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

    try {
      await ref.read(ledgerNotifierProvider.notifier).addLedger(newLedger);
    } catch (e) {
      _showWriteError(e);
    }
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

    final oldName = ledger.name;
    final oldBaseCurrencyCode = ledger.baseCurrencyCode;
    final oldExchangeRateToCNY = ledger.exchangeRateToCNY;
    final oldPersonUuids = List<String>.from(ledger.personUuids);

    ledger.name = result.name;
    ledger.baseCurrencyCode = result.baseCurrencyCode;
    ledger.exchangeRateToCNY = result.exchangeRateToCNY;
    ledger.personUuids = result.personIds;

    try {
      await ref.read(ledgerNotifierProvider.notifier).updateLedger(ledger);
    } catch (e) {
      ledger.name = oldName;
      ledger.baseCurrencyCode = oldBaseCurrencyCode;
      ledger.exchangeRateToCNY = oldExchangeRateToCNY;
      ledger.personUuids = oldPersonUuids;
      _showWriteError(e);
    }
  }

  void _deleteLedger(Ledger ledger) async {
    try {
      await ref.read(ledgerNotifierProvider.notifier).deleteLedger(ledger.uuid);

      await LastSelectedLedgerPreference.clearIfMatches(ledger.uuid);
    } catch (e) {
      _showWriteError(e);
    }
  }

  void _openLedger(Ledger ledger) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LedgerDashboardPage(ledger: ledger)),
    );
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失败，请重试：$error')));
  }
}
