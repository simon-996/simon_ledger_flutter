import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/ledger.dart';
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
    if (ledgers.isEmpty) {
      return _EmptyState(onCreate: onCreate);
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: ledgers.length,
      onReorder: (oldIndex, newIndex) {
        ref.read(ledgerNotifierProvider.notifier).reorderLedgers(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final ledger = ledgers[index];
        final stats = ledgerStats[ledger.uuid] ?? {'expense': 0.0, 'income': 0.0, 'balance': 0.0};
        final expense = stats['expense']!;
        final income = stats['income']!;
        final balance = stats['balance']!;

        return Dismissible(
          key: ValueKey(ledger.uuid),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('删除账本'),
                content: Text('确定要删除账本“${ledger.name}”吗？\n删除后无法恢复。'),
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
          },
          onDismissed: (_) => onDelete(ledger),
          background: Container(
            color: Theme.of(context).colorScheme.error,
            alignment: Alignment.centerRight,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Padding(
              padding: EdgeInsets.only(right: 24),
              child: Icon(Icons.delete, color: Colors.white),
            ),
          ),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.book,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                ledger.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '默认币种：${ledger.baseCurrencyCode} ${ledger.exchangeRateToCNY != 1.0 ? "(汇率 ${ledger.exchangeRateToCNY})" : ""}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          '收 ${income.toStringAsFixed(2)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '支 ${expense.toStringAsFixed(2)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '余 ${balance.toStringAsFixed(2)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => onEdit(ledger),
                  ),
                  Icon(
                    Icons.drag_handle,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
              onTap: () => onTap(ledger),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '还没有账本',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '先创建一个账本，并设置默认币种。\n数据仅保存在本机。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('添加账本'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
