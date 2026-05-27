import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/person_transaction_stats.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../../transactions/presentation/widgets/transaction_detail_sheet.dart';

enum TimeFilter { week, month, year, all }

class StatisticsTab extends ConsumerStatefulWidget {
  const StatisticsTab({super.key, required this.ledgers});

  final List<Ledger> ledgers;

  @override
  ConsumerState<StatisticsTab> createState() => _StatisticsTabState();
}

class _StatisticsTabState extends ConsumerState<StatisticsTab> {
  String? _selectedLedgerUuid;
  TimeFilter _timeFilter = TimeFilter.month;
  int _transactionType = 0;
  String _displayCurrency = 'CNY';

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  @override
  void didUpdateWidget(covariant StatisticsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ledgers == oldWidget.ledgers) return;

    if (_selectedLedgerUuid != null) {
      final exists = widget.ledgers.any((l) => l.uuid == _selectedLedgerUuid);
      if (!exists) {
        setState(() {
          _selectedLedgerUuid = widget.ledgers.isNotEmpty
              ? widget.ledgers.first.uuid
              : null;
        });
      }
      return;
    }

    if (widget.ledgers.isNotEmpty) {
      setState(() {
        _selectedLedgerUuid = widget.ledgers.first.uuid;
      });
    }
  }

  void _initDefaults() {
    if (widget.ledgers.isNotEmpty) {
      _selectedLedgerUuid = widget.ledgers.first.uuid;
    }
  }

  List<TransactionRecord> _filterTransactions(
    List<TransactionRecord> transactions,
  ) {
    final now = DateTime.now();
    return transactions.where((t) {
      if (t.type != _transactionType) return false;

      switch (_timeFilter) {
        case TimeFilter.week:
          final diff = now.difference(t.createdAt).inDays;
          return diff <= 7;
        case TimeFilter.month:
          return t.createdAt.year == now.year && t.createdAt.month == now.month;
        case TimeFilter.year:
          return t.createdAt.year == now.year;
        case TimeFilter.all:
          return true;
      }
    }).toList();
  }

  Map<String, double> _aggregateByCategory(
    List<TransactionRecord> transactions,
    Ledger ledger,
    String displayCurrency,
  ) {
    final map = <String, double>{};
    for (final t in transactions) {
      map[t.category] =
          (map[t.category] ?? 0.0) +
          transactionAmountForDisplay(t, ledger, displayCurrency);
    }
    return map;
  }

  Color _getColorForCategory(int index, BuildContext context) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.error,
      Colors.orange.shade500,
      Colors.purple.shade400,
      Colors.cyan.shade500,
      Colors.indigo.shade400,
      Colors.lime.shade600,
      Colors.pink.shade400,
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ledgers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bar_chart_rounded,
        title: '暂无统计数据',
        message: '先创建账本并添加流水后，再查看分类占比和人员结余。',
      );
    }

    if (_selectedLedgerUuid == null) {
      return const AppLoadingState(
        title: '正在准备统计',
        message: '读取账本和筛选条件',
        icon: Icons.bar_chart_outlined,
      );
    }

    final currentLedger = widget.ledgers.firstWhere(
      (l) => l.uuid == _selectedLedgerUuid,
      orElse: () => widget.ledgers.first,
    );

    final transactionsAsyncValue = ref.watch(
      transactionNotifierProvider(_selectedLedgerUuid!),
    );
    final peopleAsyncValue = ref.watch(
      personNotifierProvider(
        includeDeleted: true,
        ledgerUuid: _selectedLedgerUuid,
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.pagePadding,
            8,
            AppTheme.pagePadding,
            12,
          ),
          child: AppAnimatedEntry(
            child: AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ResponsiveControls(
                    first: DropdownButtonFormField<String>(
                      key: ValueKey('stats-ledger-$_selectedLedgerUuid'),
                      initialValue: _selectedLedgerUuid,
                      decoration: const InputDecoration(
                        labelText: '账本',
                        prefixIcon: Icon(Icons.book_outlined),
                      ),
                      isExpanded: true,
                      items: widget.ledgers
                          .map(
                            (l) => DropdownMenuItem(
                              value: l.uuid,
                              child: _LedgerDropdownItem(ledger: l),
                            ),
                          )
                          .toList(),
                      selectedItemBuilder: (context) => widget.ledgers
                          .map((l) => _SelectedLedgerText(ledger: l))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedLedgerUuid = val);
                        }
                      },
                    ),
                    second: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.remove_rounded),
                          label: Text('支出'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.add_rounded),
                          label: Text('收入'),
                        ),
                      ],
                      selected: {_transactionType},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() => _transactionType = newSelection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<TimeFilter>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TimeFilter.week,
                          label: Text('近7天'),
                        ),
                        ButtonSegment(
                          value: TimeFilter.month,
                          label: Text('本月'),
                        ),
                        ButtonSegment(
                          value: TimeFilter.year,
                          label: Text('本年'),
                        ),
                        ButtonSegment(value: TimeFilter.all, label: Text('全部')),
                      ],
                      selected: {_timeFilter},
                      onSelectionChanged: (Set<TimeFilter> newSelection) {
                        setState(() => _timeFilter = newSelection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: transactionsAsyncValue.when(
            loading: () => const AppLoadingState(
              title: '正在加载统计',
              message: '计算分类占比和人员结余',
              icon: Icons.pie_chart_outline_rounded,
            ),
            error: (err, stack) => AppEmptyState(
              icon: Icons.error_outline_rounded,
              title: '加载统计失败',
              message: FriendlyError.message(err, fallback: '暂时无法加载统计，请稍后重试。'),
            ),
            data: (allTransactions) {
              final displayCurrencies = supportedCurrenciesForLedger(
                currentLedger,
              );
              if (!displayCurrencies.contains(_displayCurrency)) {
                _displayCurrency = 'CNY';
              }
              final filtered = _filterTransactions(allTransactions);
              if (filtered.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.pie_chart_outline_rounded,
                  title: '该时间段内没有记录',
                  message: '切换时间范围或收支类型后再查看。',
                );
              }

              final categoryMap = _aggregateByCategory(
                filtered,
                currentLedger,
                _displayCurrency,
              );
              final sortedCategories = categoryMap.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final totalAmount = sortedCategories.fold<double>(
                0,
                (sum, item) => sum + item.value,
              );
              final sortedTransactions = List<TransactionRecord>.from(filtered)
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              final personStats = calculatePersonTransactionStats(
                sortedTransactions,
                amountOf: (transaction) => transactionAmountForDisplay(
                  transaction,
                  currentLedger,
                  _displayCurrency,
                ),
              );
              final personBalances = personStats.personBalances;

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: AppAnimatedEntry(
                        delay: const Duration(milliseconds: 70),
                        child: _SummaryChartCard(
                          title: '总${_transactionType == 0 ? "支出" : "收入"}',
                          amount: formatMoney(_displayCurrency, totalAmount),
                          isExpense: _transactionType == 0,
                          categories: sortedCategories,
                          totalAmount: totalAmount,
                          displayCurrencies: displayCurrencies,
                          selectedCurrency: _displayCurrency,
                          onCurrencyChanged: (currency) {
                            setState(() => _displayCurrency = currency);
                          },
                          colorForIndex: (index) =>
                              _getColorForCategory(index, context),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: AppSectionHeader(
                        title: '分类占比',
                        trailing: Text(
                          '${sortedCategories.length} 类',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: sortedCategories.length,
                    itemBuilder: (context, index) {
                      final entry = sortedCategories[index];
                      final percentage = entry.value / totalAmount * 100;
                      final delayMs = 100 + (index < 6 ? index : 6) * 35;
                      return AppAnimatedEntry(
                        delay: Duration(milliseconds: delayMs),
                        child: _CategoryBreakdownTile(
                          color: _getColorForCategory(index, context),
                          category: entry.key,
                          amount: formatMoney(_displayCurrency, entry.value),
                          percentage: '${percentage.toStringAsFixed(1)}%',
                        ),
                      );
                    },
                  ),
                  peopleAsyncValue.when(
                    loading: () => const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: AppInlineLoadingCard(message: '正在加载人员结余'),
                      ),
                    ),
                    error: (e, st) => SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AppSectionCard(
                          child: Text(
                            FriendlyError.message(
                              e,
                              fallback: '人员结余加载失败，请稍后重试。',
                            ),
                          ),
                        ),
                      ),
                    ),
                    data: (peoplePool) {
                      final personMap = peopleByUuid(peoplePool);
                      final peopleInLedger = personBalances.keys.map((pid) {
                        return personOrFallback(personMap, pid);
                      }).toList();

                      if (peopleInLedger.isEmpty) {
                        return const SliverToBoxAdapter(
                          child: SizedBox.shrink(),
                        );
                      }

                      return SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                              child: Text(
                                _transactionType == 0 ? '人员承担' : '人员收入',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            SizedBox(
                              height: 112,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: peopleInLedger.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final p = peopleInLedger[index];
                                  final pBalance =
                                      personBalances[p.uuid] ?? 0.0;
                                  return AppAnimatedEntry(
                                    delay: Duration(
                                      milliseconds:
                                          120 + (index < 6 ? index : 6) * 35,
                                    ),
                                    child: AppPersonBalanceCard(
                                      avatar: p.avatar,
                                      name: p.name,
                                      balance: formatMoney(
                                        _displayCurrency,
                                        pBalance,
                                        signed: true,
                                      ),
                                      isPositive: pBalance >= 0,
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (personStats.settlements.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: AppSectionCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '代付结算',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 10),
                                      ...personStats.settlements.take(5).map((
                                        settlement,
                                      ) {
                                        final from = personOrFallback(
                                          personMap,
                                          settlement.fromPersonUuid,
                                        );
                                        final to = personOrFallback(
                                          personMap,
                                          settlement.toPersonUuid,
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: AppSettlementTile(
                                            fromAvatar: from.avatar,
                                            fromName: from.name,
                                            toAvatar: to.avatar,
                                            toName: to.name,
                                            amount: formatMoney(
                                              _displayCurrency,
                                              settlement.amount,
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
                      );
                    },
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: AppSectionHeader(
                        title: '明细记录',
                        trailing: Text(
                          '${sortedTransactions.length} 条',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
                  peopleAsyncValue.when(
                    loading: () =>
                        const SliverToBoxAdapter(child: SizedBox.shrink()),
                    error: (e, st) =>
                        const SliverToBoxAdapter(child: SizedBox.shrink()),
                    data: (peoplePool) {
                      final personMap = peopleByUuid(peoplePool);
                      return SliverList.builder(
                        itemCount: sortedTransactions.length,
                        itemBuilder: (context, index) {
                          final t = sortedTransactions[index];
                          final dateStr =
                              '${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')} ${t.createdAt.hour.toString().padLeft(2, '0')}:${t.createdAt.minute.toString().padLeft(2, '0')}';
                          final peopleStr = avatarsForPeople(
                            personMap,
                            t.personUuids,
                          );

                          final delayMs = (index < 8 ? index : 8) * 28;
                          return AppAnimatedEntry(
                            delay: Duration(milliseconds: delayMs),
                            child: AppTransactionTile(
                              category: t.category,
                              date: dateStr,
                              people: peopleStr,
                              note: t.note,
                              createdByText: t.createdByNickname,
                              createdByAvatar: t.createdByAvatar,
                              amount: formatTransactionPrimaryAmount(t),
                              convertedAmount: formatTransactionConvertedAmount(
                                t,
                                currentLedger,
                              ),
                              isExpense: t.type == 0,
                              syncStatus: _syncStatusFor(t),
                              syncError: t.syncError,
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => TransactionDetailSheet(
                                    transaction: t,
                                    peoplePool: peoplePool,
                                    ledger: currentLedger,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  TransactionSyncStatus? _syncStatusFor(TransactionRecord transaction) {
    if (!transaction.pendingSync) {
      return null;
    }
    final error = transaction.syncError;
    if (error != null && error.isNotEmpty) {
      return TransactionSyncStatus.failed;
    }
    return TransactionSyncStatus.pending;
  }
}

class _SummaryChartCard extends StatelessWidget {
  const _SummaryChartCard({
    required this.title,
    required this.amount,
    required this.isExpense,
    required this.categories,
    required this.totalAmount,
    required this.displayCurrencies,
    required this.selectedCurrency,
    required this.onCurrencyChanged,
    required this.colorForIndex,
  });

  final String title;
  final String amount;
  final bool isExpense;
  final List<MapEntry<String, double>> categories;
  final double totalAmount;
  final List<String> displayCurrencies;
  final String selectedCurrency;
  final ValueChanged<String> onCurrencyChanged;
  final Color Function(int index) colorForIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isExpense ? colorScheme.error : colorScheme.primary;

    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      color: accent.withValues(alpha: 0.07),
      borderColor: accent.withValues(alpha: 0.13),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
          ),
          if (displayCurrencies.length > 1) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: displayCurrencies
                  .map(
                    (currency) =>
                        ButtonSegment(value: currency, label: Text(currency)),
                  )
                  .toList(),
              selected: {selectedCurrency},
              onSelectionChanged: (selection) {
                onCurrencyChanged(selection.first);
              },
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 210,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 46,
                sections: List.generate(categories.length, (index) {
                  final entry = categories[index];
                  final percentage = entry.value / totalAmount * 100;
                  return PieChartSectionData(
                    color: colorForIndex(index),
                    value: entry.value,
                    title: '${percentage.toStringAsFixed(0)}%',
                    radius: 58,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownTile extends StatelessWidget {
  const _CategoryBreakdownTile({
    required this.color,
    required this.category,
    required this.amount,
    required this.percentage,
  });

  final Color color;
  final String category;
  final String amount;
  final String percentage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: AppSectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    percentage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  amount,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerDropdownItem extends StatelessWidget {
  const _LedgerDropdownItem({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ledger.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          ledger.displayCode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SelectedLedgerText extends StatelessWidget {
  const _SelectedLedgerText({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    return Text(
      ledger.displayNameWithCode,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ResponsiveControls extends StatelessWidget {
  const _ResponsiveControls({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: second),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            second,
          ],
        );
      },
    );
  }
}
