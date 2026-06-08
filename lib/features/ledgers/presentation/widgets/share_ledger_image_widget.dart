import 'package:flutter/material.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/person_transaction_stats.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/theme/app_theme.dart';

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
    final balanceColor = balance >= 0
        ? AppTheme.successColor
        : AppTheme.errorColor;

    return Container(
      width: double.infinity,
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShareCard(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              children: [
                Text(
                  ledger.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onSurfaceColor,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ledger.displayCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.secondaryColor,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '结余 (CNY)',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.secondaryColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  balance.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: balanceColor,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _ShareSummaryItem(
                        label: '总收入',
                        amount: totalIncome,
                        color: AppTheme.successColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ShareSummaryItem(
                        label: '总支出',
                        amount: totalExpense,
                        color: AppTheme.errorColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (peopleInImage.isNotEmpty)
            _ShareCard(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: peopleInImage.map((p) {
                  final pBalance = personBalances[p.uuid] ?? 0.0;
                  final isPositive = pBalance >= 0;
                  final amountColor = isPositive
                      ? AppTheme.successColor
                      : AppTheme.errorColor;
                  return Container(
                    width: 104,
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE0E2E8)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.avatar, style: const TextStyle(fontSize: 21)),
                        const SizedBox(height: 5),
                        Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.onSurfaceColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          formatMoney('CNY', pBalance, signed: true),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: amountColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          if (includeTransactions) ...[
            const SizedBox(height: 14),
            _ShareCard(
              padding: EdgeInsets.zero,
              child: transactions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(
                        child: Text(
                          '暂无流水明细',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.secondaryColor,
                            fontWeight: FontWeight.w600,
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
                          fallbackAvatar: '?',
                        );
                        final amountColor = t.type == 0
                            ? AppTheme.errorColor
                            : AppTheme.successColor;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFFEDEEF2),
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
                                        Flexible(
                                          child: Text(
                                            t.category,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: AppTheme.onSurfaceColor,
                                            ),
                                          ),
                                        ),
                                        if (peopleAvatars.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              peopleAvatars,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.secondaryColor,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF8A8F99),
                                      ),
                                    ),
                                    if (t.note.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        t.note,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.secondaryColor,
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
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: amountColor,
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
          const SizedBox(height: 22),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount.toStringAsFixed(2),
              maxLines: 1,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
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
          color: Color(0xFF8A8F99),
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E2E8)),
      ),
      child: child,
    );
  }
}
