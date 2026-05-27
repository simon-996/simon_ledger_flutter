import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/widgets/app_components.dart';
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
    final dateStr =
        '${transaction.createdAt.year}-${transaction.createdAt.month.toString().padLeft(2, '0')}-${transaction.createdAt.day.toString().padLeft(2, '0')} ${transaction.createdAt.hour.toString().padLeft(2, '0')}:${transaction.createdAt.minute.toString().padLeft(2, '0')}';
    final colorScheme = Theme.of(context).colorScheme;
    final accent = transaction.type == 0
        ? colorScheme.error
        : colorScheme.primary;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;

    final splitAmount = transaction.personUuids.isNotEmpty
        ? transaction.amount / transaction.personUuids.length
        : transaction.amount;
    final personMap = peopleByUuid(peoplePool);
    final payer = transaction.payerPersonUuid == null
        ? null
        : personOrFallback(personMap, transaction.payerPersonUuid!);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction.type == 0 ? '支出明细' : '收入明细',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${transaction.currencyCode} ${transaction.amount.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: accent,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final updated = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (context) => EditTransactionSheet(
                          transaction: transaction,
                          ledger: ledger,
                        ),
                      );
                      if (updated == true && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: colorScheme.error,
                    ),
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
                                backgroundColor: colorScheme.error,
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true && context.mounted) {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        try {
                          await ref
                              .read(
                                transactionNotifierProvider(
                                  ledger.uuid,
                                ).notifier,
                              )
                              .deleteTransaction(transaction.uuid);
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                FriendlyError.message(
                                  e,
                                  fallback: '删除失败，请稍后重试。',
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              context,
                              Icons.book_outlined,
                              '账本',
                              ledger.displayNameWithCode,
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1),
                            ),
                            _buildDetailRow(
                              context,
                              Icons.access_time_rounded,
                              '时间',
                              dateStr,
                            ),
                            if (transaction.createdByNickname != null &&
                                transaction.createdByNickname!
                                    .trim()
                                    .isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1),
                              ),
                              _buildDetailRow(
                                context,
                                Icons.person_outline_rounded,
                                '添加人',
                                '${transaction.createdByAvatar ?? ''} ${transaction.createdByNickname}'
                                    .trim(),
                              ),
                            ],
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1),
                            ),
                            _buildDetailRow(
                              context,
                              Icons.category_outlined,
                              '分类',
                              transaction.category,
                            ),
                            if (transaction.type == 0) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1),
                              ),
                              _buildDetailRow(
                                context,
                                payer == null
                                    ? Icons.account_balance_wallet_outlined
                                    : Icons.person_outline_rounded,
                                '支出方式',
                                payer == null
                                    ? '共同钱包'
                                    : '${payer.avatar} ${payer.name} 代付',
                              ),
                            ],
                            if (transaction.note.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1),
                              ),
                              _buildDetailRow(
                                context,
                                Icons.notes_outlined,
                                '备注',
                                transaction.note,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppSectionHeader(
                        title:
                            '${transaction.type == 0 ? '使用人员' : '参与人员'} (${transaction.personUuids.length}人)',
                      ),
                      const SizedBox(height: 10),
                      ...transaction.personUuids.map((pid) {
                        final person = personOrFallback(personMap, pid);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppSectionCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  person.avatar,
                                  style: const TextStyle(fontSize: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${transaction.currencyCode} ${splitAmount.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: accent,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
