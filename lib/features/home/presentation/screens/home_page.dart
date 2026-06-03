import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/preferences/last_selected_ledger_preference.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/account_tab.dart';
import '../../../transactions/presentation/widgets/bookkeeping_tab.dart';
import '../../../ledgers/presentation/widgets/ledger_list_tab.dart';
import '../../../ledgers/presentation/widgets/create_ledger_sheet.dart';
import '../../../ledgers/presentation/widgets/ledger_invite_widgets.dart';
import '../../../ledgers/presentation/screens/ledger_dashboard_page.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../../../statistics/presentation/widgets/statistics_tab.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    // 监听 Provider
    final ledgersAsyncValue = ref.watch(ledgerNotifierProvider);
    final ledgerStatsAsyncValue = ref.watch(ledgerStatsProvider);
    final isAccountTab = _currentIndex == 3;
    final showLedgerFab =
        _currentIndex == 1 && ledgersAsyncValue.valueOrNull?.isNotEmpty == true;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: _currentIndex == 0 ? null : AppBar(title: Text(_appBarTitle)),
      body: SafeArea(
        top: _currentIndex == 0,
        child: isAccountTab
            ? const AccountTab()
            : ledgersAsyncValue.when(
                loading: () => const AppLoadingState(
                  title: '正在加载账本',
                  message: '同步账本、人员和本地缓存状态',
                  icon: Icons.book_outlined,
                ),
                error: (err, stack) => AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: '加载账本失败',
                  message: FriendlyError.message(
                    err,
                    fallback: '暂时无法加载账本，请检查网络后重试。',
                  ),
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
                          onShare: _shareLedger,
                          onDelete: _deleteLedger,
                          onCreate: _openCreateLedger,
                          onSync: _syncLedger,
                          autoSyncEnabled: _currentIndex == 1,
                        ),
                        error: (err, stack) => LedgerListTab(
                          ledgers: ledgers,
                          ledgerStats: const {},
                          onTap: _openLedger,
                          onEdit: _editLedger,
                          onShare: _shareLedger,
                          onDelete: _deleteLedger,
                          onCreate: _openCreateLedger,
                          onSync: _syncLedger,
                          autoSyncEnabled: _currentIndex == 1,
                        ),
                        data: (stats) => LedgerListTab(
                          ledgers: ledgers,
                          ledgerStats: stats,
                          onTap: _openLedger,
                          onEdit: _editLedger,
                          onShare: _shareLedger,
                          onDelete: _deleteLedger,
                          onCreate: _openCreateLedger,
                          onSync: _syncLedger,
                          autoSyncEnabled: _currentIndex == 1,
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
        child: showLedgerFab
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
      final token = await ref.read(authTokenProvider.future);
      final isCloudMode = token != null && token.isValid;
      if (isCloudMode) {
        await ref
            .read(ledgerNotifierProvider.notifier)
            .addLedgerWithPeople(newLedger, result.people);
      } else {
        await ref.read(ledgerNotifierProvider.notifier).addLedger(newLedger);
      }
      if (!isCloudMode && result.includeSelf) {
        await _addSelfToLedgerWithRetry(newLedger);
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
      final personRepository = ref.read(personRepositoryProvider);
      for (final person in result.people) {
        await personRepository.savePerson(person, ledgerUuid: ledger.uuid);
      }
      if (result.people.isNotEmpty) {
        ref.invalidate(personNotifierProvider);
        ref.invalidate(cachedPeopleProvider);
      }
      await _syncRemoteLedgerPeopleSelection(
        ledger.uuid,
        oldPersonUuids,
        result.personIds,
      );
      ref.invalidate(ledgerSyncStatusProvider(ledger.uuid));
      ref.invalidate(syncOverviewProvider);
      if (!mounted) return;
      AppNotice.success(
        context,
        ledger.isLocalOnly ? '账本修改已保存' : '账本修改已保存在本机，将自动同步',
      );
    } catch (e) {
      ledger.name = oldName;
      ledger.baseCurrencyCode = oldBaseCurrencyCode;
      ledger.exchangeRateToCNY = oldExchangeRateToCNY;
      ledger.personUuids = oldPersonUuids;
      _showWriteError(e);
    }
  }

  Future<void> _syncRemoteLedgerPeopleSelection(
    String ledgerUuid,
    List<String> oldPersonUuids,
    List<String> newPersonUuids,
  ) async {
    final token = await ref.read(authTokenProvider.future);
    if (token == null || !token.isValid) {
      return;
    }

    final removedPersonUuids = oldPersonUuids
        .where((uuid) => !newPersonUuids.contains(uuid))
        .toList();
    if (removedPersonUuids.isEmpty) {
      return;
    }

    final personRepository = ref.read(personRepositoryProvider);
    for (final personUuid in removedPersonUuids) {
      await personRepository.deletePerson(personUuid, ledgerUuid: ledgerUuid);
    }
    ref.invalidate(personNotifierProvider);
    ref.invalidate(cachedPeopleProvider);
    ref.invalidate(ledgerNotifierProvider);
  }

  Future<void> _deleteLedger(Ledger ledger) async {
    await ref.read(ledgerNotifierProvider.notifier).deleteLedger(ledger.uuid);
    await LastSelectedLedgerPreference.clearIfMatches(ledger.uuid);
    ref.invalidate(ledgerStatsProvider);
    ref.invalidate(syncOverviewProvider);
  }

  void _openLedger(Ledger ledger) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LedgerDashboardPage(ledger: ledger)),
    );
  }

  Future<void> _syncLedger(Ledger ledger) async {
    try {
      final result = await ref
          .read(syncCoordinatorProvider)
          .syncLedger(ledger.uuid, force: true);
      ref.invalidate(ledgerNotifierProvider);
      ref.invalidate(personNotifierProvider);
      ref.invalidate(cachedPeopleProvider);
      ref.invalidate(ledgerSyncStatusProvider(ledger.uuid));
      ref.invalidate(transactionNotifierProvider(ledger.uuid));
      ref.invalidate(ledgerStatsProvider);
      ref.invalidate(syncOverviewProvider);
      if (!mounted) return;

      final error = result.error;
      if (error != null) {
        AppNotice.error(
          context,
          FriendlyError.message(error, fallback: '部分数据同步失败，请稍后重试。'),
        );
        return;
      }

      AppNotice.success(context, '同步完成');
    } catch (error) {
      _showWriteError(error);
    }
  }

  Future<void> _shareLedger(Ledger ledger) async {
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .getCurrentInvite(ledger.remoteSyncUuid);
      if (!mounted) return;
      await showLedgerInviteShareSheet(
        context: context,
        ledgerUuid: ledger.remoteSyncUuid,
        initialInvite: invite,
      );
    } catch (error) {
      _showWriteError(error);
    }
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
    ref.invalidate(cachedPeopleProvider);
    return person.uuid;
  }

  Future<void> _addSelfToLedgerWithRetry(Ledger ledger) async {
    try {
      await _addSelfToLedger(ledger);
    } catch (error) {
      _showSelfJoinError(ledger, error);
    }
  }

  Future<void> _addSelfToLedger(Ledger ledger) async {
    final selfPersonUuid = await _ensureSelfPerson(ledger.uuid);
    if (ledger.personUuids.contains(selfPersonUuid)) {
      return;
    }

    ledger.personUuids = [...ledger.personUuids, selfPersonUuid];
    await ref.read(ledgerNotifierProvider.notifier).updateLedger(ledger);
  }

  void _showSelfJoinError(Ledger ledger, Object error) {
    if (!mounted) return;
    AppNotice.error(
      context,
      FriendlyError.message(error, fallback: '账本已创建，但暂时无法加入本人，请稍后重试。'),
      actionLabel: '重试',
      onAction: () => _addSelfToLedgerWithRetry(ledger),
    );
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    AppNotice.error(
      context,
      FriendlyError.message(error, fallback: '操作失败，请稍后重试。'),
    );
  }
}
