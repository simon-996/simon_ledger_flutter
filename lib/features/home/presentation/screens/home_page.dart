import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/preferences/last_selected_ledger_preference.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/account_tab.dart';
import '../../../transactions/presentation/widgets/bookkeeping_tab.dart';
import '../../../ledgers/presentation/widgets/ledger_list_tab.dart';
import '../../../ledgers/presentation/widgets/create_ledger_sheet.dart';
import '../../../ledgers/presentation/screens/ledger_dashboard_page.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
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
    final isAccountTab = _currentIndex == 3;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: _currentIndex == 0 ? null : AppBar(title: Text(_appBarTitle)),
      body: SafeArea(
        top: _currentIndex == 0,
        child: isAccountTab
            ? const AccountTab()
            : ledgersAsyncValue.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: '加载账本失败',
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
                label: const Text('添加账本'),
              )
            : const SizedBox.shrink(key: ValueKey('empty-fab')),
      ),
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
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: '我的',
          ),
        ],
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
      if (result.includeSelf) {
        final selfPersonUuid = await _ensureSelfPerson(newLedger.uuid);
        if (!newLedger.personUuids.contains(selfPersonUuid)) {
          newLedger.personUuids = [...newLedger.personUuids, selfPersonUuid];
          await ref
              .read(ledgerNotifierProvider.notifier)
              .updateLedger(newLedger);
        }
      }
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

  Future<String> _ensureSelfPerson(String ledgerUuid) async {
    final profile = await ref.read(localProfileProvider.future);
    final token = await ref.read(authTokenProvider.future);
    final isCloudMode = token != null && token.isValid;
    final personRepository = ref.read(personRepositoryProvider);
    final ledgerScope = isCloudMode ? ledgerUuid : null;
    final user = isCloudMode
        ? await ref.read(currentUserProvider.future)
        : null;
    final people = await personRepository.getAllPeople(ledgerUuid: ledgerScope);
    final nickname = profile.normalizedNickname;
    final existing = people.where((person) {
      if (person.isDeleted) {
        return false;
      }

      if (isCloudMode && user != null) {
        return person.linkedUserUuid == user.uuid;
      }

      return person.uuid == 'self' ||
          person.uuid == 'p1' ||
          person.name.trim() == nickname;
    }).firstOrNull;

    if (existing != null) {
      return existing.uuid;
    }

    final person = Person()
      ..uuid = isCloudMode
          ? 'self-${DateTime.now().microsecondsSinceEpoch}'
          : 'self'
      ..name = nickname
      ..avatar = profile.personAvatar
      ..linkedUserUuid = user?.uuid;
    await personRepository.savePerson(person, ledgerUuid: ledgerScope);
    ref.invalidate(personNotifierProvider);
    return person.uuid;
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失败，请重试：$error')));
  }
}
