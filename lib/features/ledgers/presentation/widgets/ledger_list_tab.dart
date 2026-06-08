import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../providers/ledger_provider.dart';

class LedgerListTab extends ConsumerWidget {
  const LedgerListTab({
    super.key,
    required this.ledgers,
    required this.ledgerStats,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onCreate,
  });

  final List<Ledger> ledgers;
  final Map<String, Map<String, double>> ledgerStats;
  final ValueChanged<Ledger> onTap;
  final ValueChanged<Ledger> onEdit;
  final ValueChanged<Ledger> onDelete;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(authTokenProvider).valueOrNull;
    final isCloudMode = token != null && token.isValid;

    if (ledgers.isEmpty) {
      return AppEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: '还没有账本',
        message: isCloudMode
            ? '创建一个云端账本，设置默认币种后就可以开始记录。'
            : '创建一个本地账本，设置默认币种后就可以开始记录。',
        action: FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('新建账本'),
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
      itemCount: ledgers.length,
      onReorderItem: (oldIndex, newIndex) {
        if (isCloudMode) {
          return;
        }
        ref
            .read(ledgerNotifierProvider.notifier)
            .reorderLedgers(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final scale = Tween<double>(begin: 1, end: 1.025).evaluate(
              CurvedAnimation(parent: animation, curve: AppMotion.standard),
            );
            return Transform.scale(scale: scale, child: child);
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final ledger = ledgers[index];
        final stats =
            ledgerStats[ledger.uuid] ??
            {'expense': 0.0, 'income': 0.0, 'balance': 0.0};
        final delayMs = (index < 6 ? index : 6) * 45;

        return Dismissible(
          key: ValueKey(ledger.uuid),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) => _confirmDelete(context, ledger),
          onDismissed: (_) => onDelete(ledger),
          background: _DeleteBackground(),
          child: AppAnimatedEntry(
            delay: Duration(milliseconds: delayMs),
            child: _LedgerCard(
              ledger: ledger,
              income: stats['income'] ?? 0,
              expense: stats['expense'] ?? 0,
              balance: stats['balance'] ?? 0,
              index: index,
              onTap: () => onTap(ledger),
              onEdit: () => onEdit(ledger),
              canReorder: !isCloudMode,
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, Ledger ledger) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账本'),
        content: Text('确定要删除“${ledger.name}”吗？\n删除后无法恢复。'),
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
    required this.index,
    required this.onTap,
    required this.onEdit,
    required this.canReorder,
  });

  final Ledger ledger;
  final double income;
  final double expense;
  final double balance;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final bool canReorder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasRate = ledger.exchangeRateToCNY != 1.0;
    final balanceColor = AppTheme.semanticAmountColor(context, balance >= 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
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
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _MetaChip(text: ledger.baseCurrencyCode),
                              if (hasRate)
                                _MetaChip(
                                  text: '汇率 ${ledger.exchangeRateToCNY}',
                                ),
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
                    if (canReorder)
                      Tooltip(
                        message: '排序',
                        child: ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatPill(
                        label: '收入',
                        value: income.toStringAsFixed(2),
                        color: AppTheme.successColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPill(
                        label: '支出',
                        value: expense.toStringAsFixed(2),
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPill(
                        label: '结余',
                        value: balance.toStringAsFixed(2),
                        color: balanceColor,
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
    );
  }
}
