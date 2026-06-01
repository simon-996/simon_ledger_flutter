import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
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
  final ValueChanged<Ledger> onShare;
  final ValueChanged<Ledger> onDelete;
  final VoidCallback onCreate;
  final Future<void> Function(Ledger ledger) onSync;
  final bool autoSyncEnabled;

  @override
  ConsumerState<LedgerListTab> createState() => _LedgerListTabState();
}

class _LedgerListTabState extends ConsumerState<LedgerListTab> {
  bool _autoSyncing = false;
  final Set<String> _syncingLedgerUuids = {};

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

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pagePadding,
        12,
        AppTheme.pagePadding,
        96,
      ),
      itemCount: widget.ledgers.length,
      onReorderItem: (oldIndex, newIndex) {
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
              borderRadius: BorderRadius.circular(20),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final ledger = widget.ledgers[index];
        final stats =
            widget.ledgerStats[ledger.uuid] ??
            {'expense': 0.0, 'income': 0.0, 'balance': 0.0};
        final syncStatus = ref.watch(ledgerSyncStatusProvider(ledger.uuid));
        final isSyncing = _syncingLedgerUuids.contains(ledger.uuid);
        final delayMs = (index < 6 ? index : 6) * 45;
        final isLocalTemporary = isCloudMode && ledger.isLocalTemporary;

        return Dismissible(
          key: ValueKey(ledger.uuid),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) => _confirmDelete(context, ledger),
          onDismissed: (_) => widget.onDelete(ledger),
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
              isSyncing: isSyncing,
              onTap: () => widget.onTap(ledger),
              onEdit: () => widget.onEdit(ledger),
              onShare: () => widget.onShare(ledger),
              onSync: () => _syncLedger(ledger),
              canReorder: true,
              canShare:
                  isCloudMode && !isLocalTemporary && _canShare(ledger.role),
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

  Future<void> _syncLedger(Ledger ledger) async {
    if (_syncingLedgerUuids.contains(ledger.uuid)) return;
    setState(() => _syncingLedgerUuids.add(ledger.uuid));
    try {
      await widget.onSync(ledger);
    } finally {
      if (mounted) {
        setState(() => _syncingLedgerUuids.remove(ledger.uuid));
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

  Future<bool?> _confirmDelete(BuildContext context, Ledger ledger) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账本'),
        content: Text(
          '确定要删除账本“${ledger.name}”吗？\n${ledger.displayCode}\n删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
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
    required this.isSyncing,
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
  final bool isSyncing;
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
    final localManualPeople = ledger.personUuids
        .map((uuid) => personOrFallback(peopleById, uuid, name: '人员'))
        .where((person) => person.linkedUserUuid == null && !person.isDeleted)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ledger.displayCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
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
                              _MetaChip(text: ledger.baseCurrencyCode),
                              if (isCloudMode && ledger.isLocalTemporary)
                                _MetaChip(
                                  text: ledger.hasSyncedRemoteCopy
                                      ? '本地已同步'
                                      : ledger.shouldUploadToCloud
                                      ? '等待上传'
                                      : '仅本地',
                                  emphasized: ledger.shouldUploadToCloud,
                                ),
                              if (ledger.isShared)
                                _MetaChip(text: '${ledger.memberCount} 人共享'),
                              if (hasRate)
                                _MetaChip(
                                  text:
                                      '汇率 ${ledger.exchangeRateToCNY.toStringAsFixed(4)}',
                                  tooltip:
                                      '1 ${ledger.baseCurrencyCode} = ${ledger.exchangeRateToCNY.toStringAsFixed(4)} CNY',
                                ),
                              if (isSyncing)
                                const _SyncingMetaChip()
                              else if (hasPendingSync)
                                _SyncMetaChip(status: syncStatusValue!),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    ),
                    if (canShare)
                      IconButton(
                        tooltip: '分享邀请',
                        icon: const Icon(Icons.ios_share_rounded),
                        onPressed: onShare,
                      ),
                    if (canSync && (hasPendingSync || isSyncing))
                      IconButton(
                        tooltip: isSyncing ? '正在同步' : '同步待处理数据',
                        icon: AnimatedSwitcher(
                          duration: AppMotion.fast,
                          child: isSyncing
                              ? const SizedBox(
                                  key: ValueKey('ledger-sync-progress'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(
                                  Icons.sync_rounded,
                                  key: ValueKey('ledger-sync-icon'),
                                ),
                        ),
                        onPressed: isSyncing ? null : onSync,
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
                  _LedgerPeopleRows(
                    sharedMembers: ledger.members,
                    localManualPeople: localManualPeople,
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
                        value: formatMoney('CNY', balance, signed: true),
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
    );
  }
}

class _LedgerPeopleRows extends StatelessWidget {
  const _LedgerPeopleRows({
    required this.sharedMembers,
    required this.localManualPeople,
  });

  final List<LedgerMemberSummary> sharedMembers;
  final List<Person> localManualPeople;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sharedMembers.isNotEmpty)
          _LedgerPeopleLine(
            label: '共享成员',
            children: sharedMembers.map((member) {
              return _LedgerPersonChip(
                avatar: member.displayAvatar,
                name: member.displayName,
                tooltip: '${member.displayName}${_roleLabel(member.role)}',
              );
            }).toList(),
          ),
        _ManualPeopleLine(
          localManualPeople: localManualPeople,
          topPadding: sharedMembers.isNotEmpty ? 8 : 0,
        ),
      ],
    );
  }

  String _roleLabel(String? role) {
    return switch (role) {
      'owner' => ' · 所有者',
      'admin' => ' · 管理员',
      'editor' => ' · 可记账',
      'viewer' => ' · 查看',
      _ => '',
    };
  }
}

class _ManualPeopleLine extends StatelessWidget {
  const _ManualPeopleLine({
    required this.localManualPeople,
    required this.topPadding,
  });

  final List<Person> localManualPeople;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return _buildLine(localManualPeople);
  }

  Widget _buildLine(List<Person> manualPeople) {
    if (manualPeople.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: _LedgerPeopleLine(
        label: '账本人员',
        children: manualPeople.map((person) {
          return _LedgerPersonChip(
            avatar: person.avatar,
            name: person.name,
            tooltip: person.name,
          );
        }).toList(),
      ),
    );
  }
}

class _LedgerPeopleLine extends StatelessWidget {
  const _LedgerPeopleLine({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: children)),
      ],
    );
  }
}

class _LedgerPersonChip extends StatelessWidget {
  const _LedgerPersonChip({
    required this.avatar,
    required this.name,
    required this.tooltip,
  });

  final String avatar;
  final String name;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 156),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: colorScheme.surfaceContainerHighest,
              child: Text(avatar, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
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
    final text = failed
        ? '失败 ${status.failedCount}/${status.pendingCount}'
        : '待同步 ${status.pendingCount}';
    final tooltip = failed ? '同步失败：$details' : '待同步：$details';

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

class _SyncingMetaChip extends StatelessWidget {
  const _SyncingMetaChip();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            '同步中',
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
    );
  }
}
