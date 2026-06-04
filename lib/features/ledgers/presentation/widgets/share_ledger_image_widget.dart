import 'package:flutter/material.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/person_transaction_stats.dart';
import '../../../../core/models/transaction_record.dart';

class ShareLedgerImageWidget extends StatelessWidget {
  const ShareLedgerImageWidget({
    super.key,
    required this.ledger,
    required this.transactions,
    this.summaryTransactions,
    required this.peoplePool,
    this.includeTransactions = true,
    this.pageIndex,
    this.totalPages,
  });

  final Ledger ledger;
  final List<TransactionRecord> transactions;
  final List<TransactionRecord>? summaryTransactions;
  final List<Person> peoplePool;
  final bool includeTransactions;
  final int? pageIndex;
  final int? totalPages;

  @override
  Widget build(BuildContext context) {
    final summary = summaryTransactions ?? transactions;
    final personMap = peopleByUuid(peoplePool);
    final totalExpense = summary
        .where((t) => t.type == 0)
        .fold(0.0, (sum, t) => sum + transactionAmountInCny(t, ledger));
    final totalIncome = summary
        .where((t) => t.type == 1)
        .fold(0.0, (sum, t) => sum + transactionAmountInCny(t, ledger));
    final balance = totalIncome - totalExpense;
    final personBalances = calculatePersonTransactionStats(
      summary,
      amountOf: (transaction) => transactionAmountInCny(transaction, ledger),
    ).personBalances;
    final peopleInImage = personBalances.keys.map((pid) {
      return personOrFallback(personMap, pid);
    }).toList();

    final content = _ShareLedgerImageContent(
      ledger: ledger,
      transactions: transactions,
      includeTransactions: includeTransactions,
      pageIndex: pageIndex,
      totalPages: totalPages,
      personMap: personMap,
      totalExpense: totalExpense,
      totalIncome: totalIncome,
      balance: balance,
      personBalances: personBalances,
      peopleInImage: peopleInImage,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return content;
        }

        return SingleChildScrollView(
          clipBehavior: Clip.hardEdge,
          child: content,
        );
      },
    );
  }
}

class _ShareLedgerImageContent extends StatelessWidget {
  const _ShareLedgerImageContent({
    required this.ledger,
    required this.transactions,
    required this.includeTransactions,
    required this.pageIndex,
    required this.totalPages,
    required this.personMap,
    required this.totalExpense,
    required this.totalIncome,
    required this.balance,
    required this.personBalances,
    required this.peopleInImage,
  });

  final Ledger ledger;
  final List<TransactionRecord> transactions;
  final bool includeTransactions;
  final int? pageIndex;
  final int? totalPages;
  final Map<String, Person> personMap;
  final double totalExpense;
  final double totalIncome;
  final double balance;
  final Map<String, double> personBalances;
  final List<Person> peopleInImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF3F4F6),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  ledger.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ledger.displayCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '结余 (CNY)',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  balance.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ShareSummaryItem(
                        label: '总收入',
                        amount: totalIncome,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ShareSummaryItem(
                        label: '总支出',
                        amount: totalExpense,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (peopleInImage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: peopleInImage.map((p) {
                  final pBalance = personBalances[p.uuid] ?? 0.0;
                  final isPositive = pBalance >= 0;
                  return Container(
                    width: 100,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.avatar, style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatMoney('CNY', pBalance, signed: true),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPositive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          if (includeTransactions) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: transactions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(
                        child: Text(
                          '暂无流水明细',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: transactions.map((t) {
                        final dateStr =
                            '${t.createdAt.year}-${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')} ${t.createdAt.hour.toString().padLeft(2, '0')}:${t.createdAt.minute.toString().padLeft(2, '0')}';
                        final peopleAvatars = avatarsForPeople(
                          personMap,
                          t.personUuids,
                          fallbackAvatar: '👤',
                        );

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFFF3F4F6),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          t.category,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            peopleAvatars,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF4B5563),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                    ),
                                    if (t.note.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        t.note,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF6B7280),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 112,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    formatTransactionPrimaryAmount(t),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: t.type == 0
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
          const SizedBox(height: 18),
          // Footer
          _ShareFooter(pageIndex: pageIndex, totalPages: totalPages),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ShareSummaryItem extends StatelessWidget {
  const _ShareSummaryItem({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            amount.toStringAsFixed(2),
            maxLines: 1,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShareFooter extends StatelessWidget {
  const _ShareFooter({required this.pageIndex, required this.totalPages});

  final int? pageIndex;
  final int? totalPages;

  @override
  Widget build(BuildContext context) {
    final pageText = (totalPages ?? 1) > 1
        ? ' · 第 ${pageIndex ?? 1}/${totalPages ?? 1} 页'
        : '';

    return Center(
      child: Text(
        'Simon Ledger$pageText',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
