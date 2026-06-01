import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../ledgers/presentation/screens/ledger_dashboard_page.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../../../statistics/presentation/widgets/statistics_tab.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';

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
      await _syncRemoteLedgerPeopleSelection(
        ledger.uuid,
        oldPersonUuids,
        result.personIds,
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
    ref.invalidate(ledgerNotifierProvider);
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

  Future<void> _syncLedger(Ledger ledger) async {
    try {
      final result = await ref
          .read(syncCoordinatorProvider)
          .syncLedger(ledger.uuid, force: true);
      ref.invalidate(ledgerSyncStatusProvider(ledger.uuid));
      ref.invalidate(transactionNotifierProvider(ledger.uuid));
      ref.invalidate(ledgerStatsProvider);
      if (!mounted) return;

      final error = result.error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyError.message(error, fallback: '部分流水同步失败，请稍后重试。'),
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.synced > 0 ? '已同步 ${result.synced} 条流水' : '没有需要同步的流水',
          ),
        ),
      );
    } catch (error) {
      _showWriteError(error);
    }
  }

  Future<void> _shareLedger(Ledger ledger) async {
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .createInvite(ledger.uuid);
      if (!mounted) return;
      final text = 'Simon Ledger 邀请码：${invite.code}';
      await Clipboard.setData(ClipboardData(text: invite.code));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('分享账本'),
          content: SelectableText('$text\n\n对方登录后使用邀请码加入：${ledger.name}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('邀请码已复制')));
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制'),
            ),
          ],
        ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          FriendlyError.message(error, fallback: '账本已创建，但暂时无法加入本人，请稍后重试。'),
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '重试',
          onPressed: () => _addSelfToLedgerWithRetry(ledger),
        ),
      ),
    );
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(FriendlyError.message(error, fallback: '操作失败，请稍后重试。')),
      ),
    );
  }
}
