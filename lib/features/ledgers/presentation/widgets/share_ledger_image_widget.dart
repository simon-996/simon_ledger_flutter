import 'package:flutter/material.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/theme/app_theme.dart';

class ShareLedgerImageWidget extends StatelessWidget {
  const ShareLedgerImageWidget({
    super.key,
    required this.ledger,
    required this.transactions,
    this.summaryTransactions,
    required this.peoplePool,
    this.pageIndex,
    this.totalPages,
  });

  final Ledger ledger;
  final List<TransactionRecord> transactions;
  final List<TransactionRecord>? summaryTransactions;
  final List<Person> peoplePool;
  final int? pageIndex;
  final int? totalPages;

  @override
  Widget build(BuildContext context) {
    final summary = summaryTransactions ?? transactions;
    final personMap = peopleByUuid(peoplePool);
    final totalExpense = summary
        .where((t) => t.type == 0)
        .fold(0.0, (sum, t) => sum + t.amount);
    final totalIncome = summary
        .where((t) => t.type == 1)
        .fold(0.0, (sum, t) => sum + t.amount);
    final balance = totalIncome - totalExpense;
    final balanceColor = balance >= 0
        ? AppTheme.successColor
        : AppTheme.errorColor;

    final personBalances = <String, double>{};
    for (final t in summary) {
      if (t.personUuids.isEmpty) continue;
      final splitAmount = t.amount / t.personUuids.length;
      for (final pid in t.personUuids) {
        personBalances[pid] ??= 0.0;
        personBalances[pid] = t.type == 0
            ? personBalances[pid]! - splitAmount
            : personBalances[pid]! + splitAmount;
      }
    }

    final peopleInImage = personBalances.keys.map((pid) {
      return personOrFallback(personMap, pid);
    }).toList();

    return Container(
      width: 400,
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
                const SizedBox(height: 8),
                Text(
                  '结余 (${ledger.baseCurrencyCode})',
                  style: const TextStyle(
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
                      child: _buildSummaryItem(
                        '总收入',
                        totalIncome,
                        AppTheme.successColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryItem(
                        '总支出',
                        totalExpense,
                        AppTheme.errorColor,
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
                          '${isPositive ? '+' : ''}${pBalance.toStringAsFixed(2)}',
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
          const SizedBox(height: 14),
          _ShareCard(
            padding: EdgeInsets.zero,
            child: Column(
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
                      bottom: BorderSide(color: Color(0xFFEDEEF2), width: 1),
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
                      Text(
                        '${t.type == 0 ? '-' : '+'} ${t.currencyCode} ${t.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: amountColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 22),
          const Center(
            child: Text(
              'Simon Ledger',
              style: TextStyle(
                color: Color(0xFF8A8F99),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          if ((totalPages ?? 1) > 1)
            Center(
              child: Text(
                '第 ${pageIndex ?? 1}/${totalPages ?? 1} 页',
                style: const TextStyle(
                  color: Color(0xFF8A8F99),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, double amount, Color color) {
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
          Text(
            amount.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
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
