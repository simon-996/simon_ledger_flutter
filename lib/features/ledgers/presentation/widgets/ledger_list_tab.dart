import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/ledger_stats_provider.dart';

class LedgerListTab extends ConsumerStatefulWidget {
  const LedgerListTab({
    super.key,
    required this.ledgers,
    required this.ledgerStats,
    required this.onTap,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onCreate,
    required this.onSync,
    required this.autoSyncEnabled,
  });

  final List<Ledger> ledgers;
  final Map<String, Map<String, double>> ledgerStats;
  final ValueChanged<Ledger> onTap;
  final ValueChanged<Ledger> onEdit;
  final Future<void> Function(Ledger ledger) onShare;
  final Future<void> Function(Ledger ledger) onDelete;
  final VoidCallback onCreate;
  final Future<void> Function(Ledger ledger) onSync;
  final bool autoSyncEnabled;

  @override
  ConsumerState<LedgerListTab> createState() => _LedgerListTabState();
}

class _LedgerListTabState extends ConsumerState<LedgerListTab> {
  bool _autoSyncing = false;
  final Map<String, _LedgerCardOperation> _ledgerOperations = {};
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(authTokenProvider).valueOrNull;
    final isCloudMode = token != null && token.isValid;
    final peopleById = ref
        .watch(cachedPeopleProvider)
        .maybeWhen(data: peopleByUuid, orElse: () => const <String, Person>{});

    if (isCloudMode && widget.autoSyncEnabled && widget.ledgers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoSyncPendingLedgers();
      });
    }

    if (widget.ledgers.isEmpty) {
      return AppEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: '还没有账本',
        message: isCloudMode
            ? '先创建一个云端账本，并设置默认币种。'
            : '先创建一个账本，并设置默认币种。数据仅保存在本机。',
        action: FilledButton.icon(
          onPressed: widget.onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加账本'),
        ),
      );
    }

    final searchKeyword = _searchController.text.trim().toLowerCase();
    final searching = searchKeyword.isNotEmpty;
    final visibleLedgers = searching
        ? widget.ledgers
              .where(
                (ledger) =>
                    ledger.name.trim().toLowerCase().contains(searchKeyword),
              )
              .toList()
        : widget.ledgers;
    final searchField = _LedgerSearchField(
      controller: _searchController,
      resultCount: visibleLedgers.length,
      totalCount: widget.ledgers.length,
      onChanged: (_) => setState(() {}),
      onClear: () {
        _searchController.clear();
        setState(() {});
      },
    );

    if (visibleLedgers.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pagePadding,
              12,
              AppTheme.pagePadding,
              8,
            ),
            child: searchField,
          ),
          Expanded(
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              title: '没有找到匹配账本',
              message: '换个名称试试。',
              action: OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded),
                label: const Text('清除搜索'),
              ),
            ),
          ),
        ],
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: searchField,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pagePadding,
        12,
        AppTheme.pagePadding,
        96,
      ),
      itemCount: visibleLedgers.length,
      onReorderItem: (oldIndex, newIndex) {
        if (searching) return;
        ref
            .read(ledgerNotifierProvider.notifier)
            .reorderLedgers(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final elevation = Tween<double>(
              begin: 0,
              end: 8,
            ).evaluate(animation);
            return Material(
              color: Colors.transparent,
              elevation: elevation,
              borderRadius: BorderRadius.circular(28),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final ledger = visibleLedgers[index];
        final stats =
            widget.ledgerStats[ledger.uuid] ??
            {'expense': 0.0, 'income': 0.0, 'balance': 0.0};
        final syncStatus = ref.watch(ledgerSyncStatusProvider(ledger.uuid));
        final operation = _ledgerOperations[ledger.uuid];
        final isBusy = operation != null;
        final delayMs = (index < 6 ? index : 6) * 45;
        return Dismissible(
          key: ValueKey(ledger.uuid),
          direction: isBusy
              ? DismissDirection.none
              : DismissDirection.endToStart,
          confirmDismiss: (direction) => _confirmDelete(ledger),
          background: _DeleteBackground(),
          child: AppAnimatedEntry(
            delay: Duration(milliseconds: delayMs),
            child: _LedgerCard(
              ledger: ledger,
              income: stats['income'] ?? 0,
              expense: stats['expense'] ?? 0,
              balance: stats['balance'] ?? 0,
              peopleById: peopleById,
              isCloudMode: isCloudMode,
              index: index,
              syncStatus: syncStatus,
              operation: operation,
              onTap: () => widget.onTap(ledger),
              onEdit: () => widget.onEdit(ledger),
              onShare: () => _shareLedger(ledger),
              onSync: () => _syncLedger(ledger),
              canReorder: !searching,
              canShare:
                  isCloudMode &&
                  ledger.isCloudManaged &&
                  _canShare(ledger.role),
              canSync: isCloudMode,
            ),
          ),
        );
      },
    );
  }

  bool _canShare(String? role) {
    return role == 'owner' || role == 'admin';
  }

  Future<void> _shareLedger(Ledger ledger) async {
    await _runLedgerOperation(
      ledger,
      _LedgerCardOperation.share,
      () => widget.onShare(ledger),
    );
  }

  Future<void> _syncLedger(Ledger ledger) async {
    await _runLedgerOperation(
      ledger,
      _LedgerCardOperation.sync,
      () => widget.onSync(ledger),
    );
  }

  Future<void> _deleteLedger(Ledger ledger) async {
    await _runLedgerOperation(
      ledger,
      _LedgerCardOperation.delete,
      () => widget.onDelete(ledger),
    );
  }

  Future<void> _runLedgerOperation(
    Ledger ledger,
    _LedgerCardOperation operation,
    Future<void> Function() action,
  ) async {
    if (_ledgerOperations.containsKey(ledger.uuid)) return;
    setState(() => _ledgerOperations[ledger.uuid] = operation);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _ledgerOperations.remove(ledger.uuid));
      }
    }
  }

  Future<void> _autoSyncPendingLedgers() async {
    if (_autoSyncing) return;
    _autoSyncing = true;
    final syncCoordinator = ref.read(syncCoordinatorProvider);

    try {
      final changed = await syncCoordinator.syncAllPending();
      if (changed && mounted) {
        for (final ledger in widget.ledgers) {
          ref.invalidate(ledgerSyncStatusProvider(ledger.uuid));
          ref.invalidate(transactionNotifierProvider(ledger.uuid));
        }
        ref.invalidate(ledgerNotifierProvider);
        ref.invalidate(personNotifierProvider);
        ref.invalidate(ledgerStatsProvider);
        ref.invalidate(syncOverviewProvider);
      }
    } catch (_) {
      // Silent auto-sync: cards keep showing pending or failed state.
    } finally {
      _autoSyncing = false;
    }
  }

  Future<bool> _confirmDelete(Ledger ledger) async {
    final transactions = await ref
        .read(databaseProvider)
        .getTransactionsForLedger(ledger.uuid);
    if (!mounted) return false;

    final isCompact = MediaQuery.sizeOf(context).width < 640;
    final panel = _DeleteLedgerConfirmPanel(
      ledger: ledger,
      transactionCount: transactions.length,
      onDelete: () => _deleteLedger(ledger),
      compact: isCompact,
    );
    final deleted = isCompact
        ? await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            isDismissible: false,
            enableDrag: false,
            showDragHandle: true,
            builder: (context) => panel,
          )
        : await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => Dialog(child: panel),
          );
    if (deleted == true && mounted) {
      final isLeaveAction = _isLeaveLedgerAction(ledger);
      AppNotice.success(
        context,
        ledger.isLocalOnly
            ? '账本已删除'
            : isLeaveAction
            ? '已退出账本，将同步到云端'
            : '账本已在本机删除，将同步到云端',
      );
    }

    // The provider removes the ledger after its local deletion completes.
    return false;
  }
}

enum _LedgerCardOperation { share, sync, delete }

bool _isLeaveLedgerAction(Ledger ledger) {
  if (ledger.isLocalOnly) {
    return false;
  }
  final role = ledger.role?.trim().toLowerCase();
  if (role == 'owner') {
    return false;
  }
  return role != null || ledger.isShared;
}

class _LedgerSearchField extends StatelessWidget {
  const _LedgerSearchField({
    required this.controller,
    required this.resultCount,
    required this.totalCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final keyword = controller.text.trim();
    return DecoratedBox(
      key: const ValueKey('ledger-search-surface'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.62),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.025),
            blurRadius: 14,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索账本',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: keyword.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                ),
          suffixText: keyword.isEmpty ? null : '$resultCount/$totalCount',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _DeleteLedgerConfirmPanel extends StatefulWidget {
  const _DeleteLedgerConfirmPanel({
    required this.ledger,
    required this.transactionCount,
    required this.onDelete,
    required this.compact,
  });

  final Ledger ledger;
  final int transactionCount;
  final Future<void> Function() onDelete;
  final bool compact;

  @override
  State<_DeleteLedgerConfirmPanel> createState() =>
      _DeleteLedgerConfirmPanelState();
}

class _DeleteLedgerConfirmPanelState extends State<_DeleteLedgerConfirmPanel> {
  bool _deleting = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLocalOnly = widget.ledger.isLocalOnly;
    final isLeaveAction = _isLeaveAction;
    final actionColor = isLeaveAction ? colorScheme.primary : colorScheme.error;
    final actionContainerColor = isLeaveAction
        ? colorScheme.primaryContainer
        : colorScheme.errorContainer;
    final onActionContainerColor = isLeaveAction
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;
    final typeLabel = widget.ledger.shouldUploadToCloud
        ? '待同步账本'
        : isLocalOnly
        ? '本机账本'
        : isLeaveAction
        ? '共享账本'
        : '云端账本';
    final description = isLeaveAction
        ? '退出后，该账本不会再显示在你的账本列表中；其他成员和账本历史数据不会受到影响。'
        : isLocalOnly
        ? '删除后，本机中的账本和流水会立即移除。'
        : '删除后会先从本机移除；如果暂时离线，联网后会自动同步删除操作。';
    final title = isLeaveAction ? '退出账本' : '删除账本';
    final subtitle = isLeaveAction ? '仅从你的列表移除' : '此操作无法恢复';
    final icon = isLeaveAction
        ? Icons.logout_rounded
        : Icons.delete_outline_rounded;

    return PopScope(
      canPop: !_deleting,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            key: const ValueKey('delete-ledger-panel-content'),
            padding: EdgeInsets.fromLTRB(20, widget.compact ? 4 : 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: actionContainerColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: onActionContainerColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: actionColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  widget.ledger.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.ledger.displayCode,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _MetaChip(text: typeLabel),
                ),
                const SizedBox(height: 16),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.transactionCount > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: actionContainerColor.withValues(alpha: 0.54),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: actionColor.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 19,
                          color: actionColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isLeaveAction
                                ? '该账本包含 ${widget.transactionCount} 条流水，退出后仅从你的列表移除，不会删除共享账本数据。'
                                : '该账本包含 ${widget.transactionCount} 条流水，删除后无法恢复。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: onActionContainerColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _deleting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _deleting ? null : _delete,
                        style: FilledButton.styleFrom(
                          backgroundColor: actionColor,
                          foregroundColor: isLeaveAction
                              ? colorScheme.onPrimary
                              : colorScheme.onError,
                        ),
                        icon: _deleting
                            ? SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: isLeaveAction
                                      ? colorScheme.onPrimary
                                      : colorScheme.onError,
                                ),
                              )
                            : Icon(icon),
                        label: Text(
                          _deleting
                              ? (isLeaveAction ? '正在退出' : '正在删除')
                              : (isLeaveAction ? '退出' : '删除'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _errorText = null;
    });
    try {
      await widget.onDelete();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _errorText = FriendlyError.message(
          error,
          fallback: _isLeaveAction ? '退出失败，请稍后重试。' : '删除失败，请稍后重试。',
        );
      });
    }
  }

  bool get _isLeaveAction {
    return _isLeaveLedgerAction(widget.ledger);
  }
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({
    required this.ledger,
    required this.income,
    required this.expense,
    required this.balance,
    required this.peopleById,
    required this.isCloudMode,
    required this.index,
    required this.syncStatus,
    required this.operation,
    required this.onTap,
    required this.onEdit,
    required this.onShare,
    required this.onSync,
    required this.canReorder,
    required this.canShare,
    required this.canSync,
  });

  final Ledger ledger;
  final double income;
  final double expense;
  final double balance;
  final Map<String, Person> peopleById;
  final bool isCloudMode;
  final int index;
  final AsyncValue<LedgerSyncStatus> syncStatus;
  final _LedgerCardOperation? operation;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onSync;
  final bool canReorder;
  final bool canShare;
  final bool canSync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasRate = ledger.exchangeRateToCNY != 1.0;
    final syncStatusValue = syncStatus.valueOrNull;
    final hasPendingSync = syncStatusValue?.hasPending == true;
    final isBusy = operation != null;
    final isSyncing = operation == _LedgerCardOperation.sync;
    final isLocalUnsynced =
        isCloudMode && ledger.isLocalTemporary && !ledger.hasSyncedRemoteCopy;
    final isCloudSynced =
        isCloudMode && ledger.isCloudManaged && !hasPendingSync && !isSyncing;
    final localManualPeople = ledger.personUuids
        .map((uuid) => personOrFallback(peopleById, uuid, name: '人员'))
        .where((person) => person.linkedUserUuid == null && !person.isDeleted)
        .toList();
    final cardRadius = BorderRadius.circular(28);
    final cardColor = isBusy
        ? Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surfaceContainerLowest,
          )
        : colorScheme.surfaceContainerLowest;
    final borderColor = isBusy
        ? colorScheme.primary.withValues(alpha: 0.32)
        : colorScheme.outlineVariant.withValues(alpha: 0.68);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        key: ValueKey('ledger-card-surface-${ledger.uuid}'),
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: cardRadius,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(
                alpha: isBusy ? 0.08 : 0.045,
              ),
              blurRadius: isBusy ? 28 : 22,
              spreadRadius: -6,
              offset: Offset(0, isBusy ? 14 : 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: cardRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isBusy ? null : onTap,
            borderRadius: cardRadius,
            child: Stack(
              children: [
                AnimatedOpacity(
                  duration: AppMotion.normal,
                  curve: AppMotion.standard,
                  opacity: isBusy ? 0.34 : 1,
                  child: IgnorePointer(
                    ignoring: isBusy,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ledger.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      ledger.displayCode,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 7),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _MetaChip(
                                          text: ledger.baseCurrencyCode,
                                        ),
                                        if (hasPendingSync)
                                          _SyncMetaChip(
                                            status: syncStatusValue!,
                                          )
                                        else if (isLocalUnsynced)
                                          _MetaChip(
                                            text: ledger.shouldUploadToCloud
                                                ? '待同步'
                                                : '本机',
                                            emphasized:
                                                ledger.shouldUploadToCloud,
                                          ),
                                        if (ledger.isShared)
                                          _MetaChip(
                                            text: '${ledger.memberCount} 人共享',
                                          ),
                                        if (hasRate)
                                          _MetaChip(
                                            text:
                                                '汇率 ${ledger.exchangeRateToCNY.toStringAsFixed(4)}',
                                            tooltip:
                                                '1 ${ledger.baseCurrencyCode} = ${ledger.exchangeRateToCNY.toStringAsFixed(4)} CNY',
                                          ),
                                        if (isCloudSynced)
                                          const _MetaChip(
                                            text: '已同步',
                                            tooltip: '账本数据已同步至云端',
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (canSync && (hasPendingSync || isSyncing))
                                IconButton(
                                  tooltip: isSyncing ? '正在同步' : '同步待处理数据',
                                  icon: const Icon(Icons.sync_rounded),
                                  onPressed: isBusy ? null : onSync,
                                ),
                              IconButton(
                                tooltip: '编辑',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: isBusy ? null : onEdit,
                              ),
                              if (canShare)
                                IconButton(
                                  tooltip: '分享邀请',
                                  icon: const Icon(Icons.ios_share_rounded),
                                  onPressed: isBusy ? null : onShare,
                                ),
                              if (canReorder)
                                Tooltip(
                                  message: '排序',
                                  child: ReorderableDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (ledger.members.isNotEmpty ||
                              ledger.personUuids.isNotEmpty) ...[
                            AppLedgerPeopleChips(
                              sharedMembers: ledger.members,
                              localManualPeople: localManualPeople,
                              peopleById: peopleById,
                            ),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: _StatPill(
                                  label: '收入',
                                  value: formatMoney('CNY', income),
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatPill(
                                  label: '支出',
                                  value: formatMoney('CNY', expense),
                                  color: colorScheme.error,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatPill(
                                  label: '结余',
                                  value: formatMoney(
                                    'CNY',
                                    balance,
                                    signed: true,
                                  ),
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: AppMotion.normal,
                      switchInCurve: AppMotion.emphasized,
                      switchOutCurve: AppMotion.standard,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.96,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: operation == null
                          ? const SizedBox.shrink(
                              key: ValueKey('ledger-operation-idle'),
                            )
                          : _LedgerOperationOverlay(
                              key: ValueKey(operation),
                              operation: operation!,
                              isLeaveAction: _isLeaveLedgerAction(ledger),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerOperationOverlay extends StatelessWidget {
  const _LedgerOperationOverlay({
    super.key,
    required this.operation,
    required this.isLeaveAction,
  });

  final _LedgerCardOperation operation;
  final bool isLeaveAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = switch (operation) {
      _LedgerCardOperation.share => '正在生成邀请',
      _LedgerCardOperation.sync => '正在同步账本',
      _LedgerCardOperation.delete => isLeaveAction ? '正在退出账本' : '正在删除账本',
    };

    return ColoredBox(
      color: colorScheme.surface.withValues(alpha: 0.5),
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: message,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text, this.tooltip, this.emphasized = false});

  final String text;
  final String? tooltip;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip ?? text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: emphasized
              ? colorScheme.tertiaryContainer.withValues(alpha: 0.7)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: emphasized
                ? colorScheme.onTertiaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SyncMetaChip extends StatelessWidget {
  const _SyncMetaChip({required this.status});

  final LedgerSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = status.hasFailed;
    final color = failed ? colorScheme.error : colorScheme.tertiary;
    final details = [
      if (status.ledgerPendingCount > 0) '账本 ${status.ledgerPendingCount}',
      if (status.personPendingCount > 0) '人员 ${status.personPendingCount}',
      if (status.transactionPendingCount > 0)
        '流水 ${status.transactionPendingCount}',
    ].join(' · ');
    final text = failed ? '同步失败' : '待同步 ${status.pendingCount}';
    final tooltip = failed
        ? '同步失败 ${status.failedCount}/${status.pendingCount}：$details'
        : '待同步：$details';

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.sync_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: error,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
    );
  }
}
