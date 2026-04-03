import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/transaction_record.dart';
import '../providers/transaction_provider.dart';
import 'edit_transaction_sheet.dart';

class TransactionDetailSheet extends ConsumerWidget {
  const TransactionDetailSheet({
    super.key,
    required this.transaction,
    required this.peoplePool,
    required this.ledger,
  });

  final TransactionRecord transaction;
  final List<Person> peoplePool;
  final Ledger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = '${transaction.createdAt.year}-${transaction.createdAt.month.toString().padLeft(2, '0')}-${transaction.createdAt.day.toString().padLeft(2, '0')} ${transaction.createdAt.hour.toString().padLeft(2, '0')}:${transaction.createdAt.minute.toString().padLeft(2, '0')}';
    
    final splitAmount = transaction.personUuids.isNotEmpty 
        ? transaction.amount / transaction.personUuids.length 
        : transaction.amount;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  Navigator.pop(context); // close detail sheet
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (context) => EditTransactionSheet(
                      transaction: transaction,
                      ledger: ledger,
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('删除明细'),
                      content: const Text('确定要删除这条记账明细吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirm == true && context.mounted) {
                    Navigator.pop(context); // close sheet
                    ref.read(transactionNotifierProvider(ledger.uuid).notifier)
                       .deleteTransaction(transaction.uuid);
                  }
                },
              ),
            ],
          ),
          
          CircleAvatar(
            radius: 32,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              transaction.category.characters.first,
              style: TextStyle(
                fontSize: 28,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            transaction.category,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          
          Text(
            '${transaction.currencyCode} ${transaction.amount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: transaction.type == 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(context, Icons.access_time, '时间', dateStr),
                if (transaction.note.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _buildDetailRow(context, Icons.notes, '备注', transaction.note),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '参与人员 (${transaction.personUuids.length}人)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: transaction.personUuids.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final pid = transaction.personUuids[index];
                final person = peoplePool.firstWhere(
                  (p) => p.uuid == pid, 
                  orElse: () => Person()..uuid = ''..name = '未知'
                );
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(person.avatar, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          person.name,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                        ),
                      ),
                      Text(
                        '${transaction.currencyCode} ${splitAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: transaction.type == 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
