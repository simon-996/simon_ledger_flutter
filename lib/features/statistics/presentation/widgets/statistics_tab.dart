import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/person_transaction_stats.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/preferences/statistics_preference.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/transaction_date.dart';
import '../../../ledgers/presentation/screens/ledger_dashboard_page.dart';
import 'transaction_date_controls.dart';
import 'statistics_date_preference.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../../core/widgets/currency_widgets.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../../transactions/presentation/widgets/transaction_detail_sheet.dart';
import '../../../transactions/presentation/widgets/transaction_form_components.dart';

enum TimeFilter { week, month, year, all, custom }

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
  DateTime _calendarMonth = DateTime.now();
  TransactionDateRange? _customRange;

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
          _calendarMonth = DateTime.now();
          _customRange = null;
          _timeFilter = TimeFilter.month;
        });
        unawaited(_restoreDatePreference());
      }
      return;
    }

    if (widget.ledgers.isNotEmpty) {
      setState(() {
        _selectedLedgerUuid = widget.ledgers.first.uuid;
      });
      unawaited(_restoreDatePreference());
    }
  }

  Future<void> _initDefaults() async {
    final preference = await StatisticsPreference.read();
    if (!mounted) return;
    setState(() {
      _timeFilter = TimeFilter.values.firstWhere(
        (filter) => filter.name == preference?.timeFilter,
        orElse: () => TimeFilter.month,
      );
      _transactionType = preference?.transactionType == 1 ? 1 : 0;
      _displayCurrency = preference?.displayCurrency ?? 'CNY';
      final preferredLedgerUuid = preference?.ledgerUuid;
      if (widget.ledgers.any((ledger) => ledger.uuid == preferredLedgerUuid)) {
        _selectedLedgerUuid = preferredLedgerUuid;
      } else if (widget.ledgers.isNotEmpty) {
        _selectedLedgerUuid = widget.ledgers.first.uuid;
      }
    });
    await _restoreDatePreference();
  }

  Future<void> _restoreDatePreference() async {
    final uuid = _effectiveLedger()?.uuid;
    if (uuid == null) return;
    final date = await StatisticsDatePreference.read(uuid);
    if (!mounted || _effectiveLedger()?.uuid != uuid) return;
    setState(() {
      _calendarMonth = date?.month ?? DateTime.now();
      _customRange = date?.custom;
      if (date != null) {
        _timeFilter = TimeFilter.values.firstWhere(
          (f) => f.name == date.mode,
          orElse: () => TimeFilter.month,
        );
      }
      if (_timeFilter == TimeFilter.custom && _customRange == null) {
        _timeFilter = TimeFilter.month;
      }
    });
  }

  Future<void> _showLedgerPicker() async {
    final currentLedger = _effectiveLedger();
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: widget.ledgers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final ledger = widget.ledgers[index];
              final selected = ledger.uuid == currentLedger?.uuid;
              return _LedgerPickerTile(
                ledger: ledger,
                selected: selected,
                onTap: () => Navigator.of(context).pop(ledger.uuid),
              );
            },
          ),
        );
      },
    );
    if (selected == null || selected == _selectedLedgerUuid || !mounted) {
      return;
    }
    setState(() {
      _selectedLedgerUuid = selected;
      _calendarMonth = DateTime.now();
      _customRange = null;
      _timeFilter = TimeFilter.month;
    });
    await _restoreDatePreference();
    _persistPreference();
  }

  void _persistPreference() {
    final uuid = _effectiveLedger()?.uuid;
    if (uuid != null) {
      unawaited(
        StatisticsDatePreference(
          month: _calendarMonth,
          mode: _timeFilter.name,
          custom: _customRange,
        ).write(uuid),
      );
    }
    unawaited(
      StatisticsPreference.write(
        StatisticsPreference(
          ledgerUuid: _effectiveLedger()?.uuid ?? _selectedLedgerUuid,
          timeFilter: _timeFilter.name,
          transactionType: _transactionType,
          displayCurrency: _displayCurrency,
        ),
      ),
    );
  }

  Ledger? _effectiveLedger() {
    if (widget.ledgers.isEmpty) return null;
    return widget.ledgers.firstWhere(
      (ledger) => ledger.uuid == _selectedLedgerUuid,
      orElse: () => widget.ledgers.first,
    );
  }

  List<TransactionRecord> _filterTransactions(
    List<TransactionRecord> transactions,
  ) {
    final range = _selectedRange;
    return transactions
        .where(
          (t) =>
              t.type == _transactionType &&
              (range == null || range.contains(t.createdAt)),
        )
        .toList();
  }

  TransactionDateRange? get _selectedRange => switch (_timeFilter) {
    TimeFilter.week => TransactionDateRange.week(DateTime.now()),
    TimeFilter.month => TransactionDateRange.month(_calendarMonth),
    TimeFilter.year => TransactionDateRange.year(DateTime.now()),
    TimeFilter.custom => _customRange,
    TimeFilter.all => null,
  };

  void _resetFilters() {
    setState(() {
      _timeFilter = TimeFilter.month;
      _calendarMonth = DateTime.now();
      _customRange = null;
      _transactionType = 0;
      _displayCurrency = 'CNY';
    });
    _persistPreference();
  }

  void _openCategory(Ledger ledger, String category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LedgerDashboardPage(
          ledger: ledger,
          initialCategory: category,
          initialTransactionType: _transactionType,
          initialDateRange: _selectedRange,
          initialDisplayCurrency: _displayCurrency,
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    if (widget.ledgers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bar_chart_rounded,
        title: '暂无统计数据',
        message: '先创建账本并添加流水后，再查看分类占比和人员结余。',
      );
    }

    final currentLedger = _effectiveLedger()!;

    final transactionsAsyncValue = ref.watch(
      transactionProvider(currentLedger.uuid),
    );
    final peopleAsyncValue = ref.watch(
      personProvider(includeDeleted: true, ledgerUuid: currentLedger.uuid),
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
            child: _StatsFilterPanel(
              ledger: currentLedger,
              transactionType: _transactionType,
              timeFilter: _timeFilter,
              calendarMonth: _calendarMonth,
              customRange: _customRange,
              onMonthChanged: (month) {
                setState(() {
                  _calendarMonth = month;
                  _timeFilter = TimeFilter.month;
                });
                _persistPreference();
              },
              onCustomChanged: (range) {
                setState(() {
                  _customRange = range;
                  _timeFilter = TimeFilter.custom;
                });
                _persistPreference();
              },
              onReset: _resetFilters,
              onLedgerTap: _showLedgerPicker,
              onTypeChanged: (type) {
                setState(() => _transactionType = type);
                _persistPreference();
              },
              onTimeChanged: (filter) {
                setState(() {
                  _timeFilter = filter;
                  if (filter == TimeFilter.month) {
                    _calendarMonth = DateTime.now();
                  }
                });
                _persistPreference();
              },
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
              final averageAmount = sortedTransactions.isEmpty
                  ? 0.0
                  : totalAmount / sortedTransactions.length;
              final range = _selectedRange;
              final previous = range?.previous;
              final previousRecords = previous == null
                  ? <TransactionRecord>[]
                  : allTransactions
                        .where(
                          (t) =>
                              t.type == _transactionType &&
                              previous.contains(t.createdAt),
                        )
                        .toList();
              final previousAmount = previousRecords.fold<double>(
                0,
                (sum, t) =>
                    sum +
                    transactionAmountForDisplay(
                      t,
                      currentLedger,
                      _displayCurrency,
                    ),
              );
              final comparison = PeriodComparison(
                current: totalAmount,
                previous: previousAmount,
                previousCount: previousRecords.length,
              );
              final scope =
                  '本账本 · ${_transactionType == 0 ? "支出" : "收入"} · $_displayCurrency · ${range?.label ?? "全部时间"}';
              final dailyGroups = groupTransactionsByDay(
                sortedTransactions,
                amountOf: (t) => transactionAmountForDisplay(
                  t,
                  currentLedger,
                  _displayCurrency,
                ),
              );

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
                          scope: scope,
                          comparison: previous == null
                              ? '全部时间不做上期比较'
                              : comparison.label(_displayCurrency),
                          previousScope: previous == null
                              ? null
                              : '上期：${previous.label}',
                          trend: _DailyTrend(
                            groups: dailyGroups,
                            range: range,
                            isExpense: _transactionType == 0,
                            currency: _displayCurrency,
                          ),
                          amount: formatMoney(_displayCurrency, totalAmount),
                          transactionCount: sortedTransactions.length,
                          averageAmount: formatMoney(
                            _displayCurrency,
                            averageAmount,
                          ),
                          isExpense: _transactionType == 0,
                          categories: sortedCategories,
                          totalAmount: totalAmount,
                          displayCurrencies: displayCurrencies,
                          selectedCurrency: _displayCurrency,
                          onCurrencyChanged: (currency) {
                            setState(() => _displayCurrency = currency);
                            _persistPreference();
                          },
                        ),
                      ),
                    ),
                  ),
                  if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: AppEmptyState(
                        icon: Icons.pie_chart_outline_rounded,
                        title: '该时间段内没有记录',
                        message: '切换月份、日期范围或收支类型后再查看。',
                        action: TextButton(
                          onPressed: _resetFilters,
                          child: const Text('重置筛选'),
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
                      final percentage = totalAmount == 0
                          ? 0.0
                          : entry.value / totalAmount * 100;
                      final delayMs = 100 + (index < 6 ? index : 6) * 35;
                      return AppAnimatedEntry(
                        delay: Duration(milliseconds: delayMs),
                        child: _CategoryBreakdownTile(
                          key: ValueKey('statistics-category-${entry.key}'),
                          onTap: () => _openCategory(currentLedger, entry.key),
                          color: AppColors.of(context).chartColorFor(entry.key),
                          category: entry.key,
                          amount: formatMoney(_displayCurrency, entry.value),
                          percentage: '${percentage.toStringAsFixed(1)}%',
                          progress: percentage / 100,
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
                          final dateStr = transactionRowDate(
                            t.createdAt,
                            DateTime.now(),
                          );
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
                              compactSyncStatus: true,
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
    required this.transactionCount,
    required this.averageAmount,
    required this.isExpense,
    required this.categories,
    required this.totalAmount,
    required this.displayCurrencies,
    required this.selectedCurrency,
    required this.onCurrencyChanged,
    required this.scope,
    required this.comparison,
    required this.trend,
    this.previousScope,
  });

  final String title;
  final String amount;
  final int transactionCount;
  final String averageAmount;
  final bool isExpense;
  final List<MapEntry<String, double>> categories;
  final double totalAmount;
  final List<String> displayCurrencies;
  final String selectedCurrency;
  final ValueChanged<String> onCurrencyChanged;
  final String scope;
  final String comparison;
  final String? previousScope;
  final Widget trend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = transactionAccentColor(context, isExpense ? 0 : 1);
    final colors = AppColors.of(context);

    return AppSectionCard(
      key: const ValueKey('statistics-summary-card'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      color: colorScheme.surfaceContainerLowest,
      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.68),
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
                      title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: AppTheme.emphasisWeight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        amount,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: AppTheme.emphasisWeight,
                              color: accent,
                              height: 1.08,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isExpense
                      ? Icons.trending_down_rounded
                      : Icons.trending_up_rounded,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scope,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(comparison, style: Theme.of(context).textTheme.labelLarge),
          if (previousScope != null)
            Text(
              previousScope!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: '记录',
                  value: '$transactionCount 条',
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryMetric(
                  label: '平均',
                  value: averageAmount,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          if (displayCurrencies.length > 1) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: displayCurrencies
                  .map(
                    (currency) => ButtonSegment(
                      value: currency,
                      label: CurrencyLabel(code: currency, showName: false),
                    ),
                  )
                  .toList(),
              selected: {selectedCurrency},
              onSelectionChanged: (selection) {
                onCurrencyChanged(selection.first);
              },
            ),
          ],
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final pie = SizedBox(
                height: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 52,
                        sections: List.generate(categories.length, (index) {
                          final entry = categories[index];
                          final color = colors.chartColorFor(entry.key);
                          final percentage = entry.value / totalAmount * 100;
                          return PieChartSectionData(
                            color: color,
                            value: entry.value,
                            title: percentage >= 6
                                ? '${percentage.toStringAsFixed(0)}%'
                                : '',
                            radius: 58,
                            titleStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: AppTheme.headingWeight,
                              color: AppColors.foregroundFor(
                                color,
                                colorScheme,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpense
                              ? Icons.trending_down_rounded
                              : Icons.trending_up_rounded,
                          color: accent,
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '分类',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: AppTheme.headingWeight,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              if (constraints.maxWidth >= 680) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (categories.isNotEmpty && totalAmount > 0)
                      Expanded(child: pie),
                    const SizedBox(width: 24),
                    Expanded(child: trend),
                  ],
                );
              }
              return Column(
                children: [
                  if (categories.isNotEmpty && totalAmount > 0) pie,
                  const SizedBox(height: 12),
                  trend,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DailyTrend extends StatelessWidget {
  const _DailyTrend({
    required this.groups,
    required this.range,
    required this.isExpense,
    required this.currency,
  });
  final List<TransactionDayGroup> groups;
  final TransactionDateRange? range;
  final bool isExpense;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final accent = transactionAccentColor(context, isExpense ? 0 : 1);
    final colorScheme = Theme.of(context).colorScheme;
    final today = transactionDay(DateTime.now());
    final rangeEnd = range?.end ?? (groups.isEmpty ? today : groups.first.date);
    final end = rangeEnd.isAfter(today) ? today : rangeEnd;
    final originalStart =
        range?.start ?? (groups.isEmpty ? today : groups.last.date);
    if (originalStart.isAfter(end)) {
      return Text(
        '所选日期尚未开始，暂无每日趋势',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final limit = DateTime(end.year, end.month, end.day - 365);
    final start = originalStart.isBefore(limit) ? limit : originalStart;
    final dates = <DateTime>[];
    for (
      var date = start;
      !date.isAfter(end);
      date = DateTime(date.year, date.month, date.day + 1)
    ) {
      dates.add(date);
    }
    final amounts = {
      for (final group in groups)
        group.date: isExpense ? group.expense : group.income,
    };
    final values = [for (final date in dates) amounts[date] ?? 0.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '每日${isExpense ? "支出" : "收入"}趋势 · $currency',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          '截至 ${end.year}/${end.month}/${end.day}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (groups.any((group) => group.date.isAfter(today)))
          Text(
            '未来日期记录计入上方合计，未计入趋势',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (originalStart.isBefore(limit))
          Text('显示所选范围的最近366天', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Semantics(
          label: '每日金额按日期从早到晚排列，空白日期计为零',
          child: SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: dates.length <= 1 ? 1 : (dates.length - 1).toDouble(),
                minY: values.any((v) => v < 0) ? null : 0,
                maxY: values.every((v) => v == 0) ? 1 : null,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: ((dates.length - 1) / 3)
                          .ceil()
                          .clamp(1, 122)
                          .toDouble(),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= dates.length) {
                          return const SizedBox.shrink();
                        }
                        final day = dates[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${day.month}/${day.day}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((spot) {
                      final day =
                          dates[spot.x.toInt().clamp(0, dates.length - 1)];
                      return LineTooltipItem(
                        '${day.year}/${day.month}/${day.day}\n${formatMoney(currency, spot.y)}',
                        TextStyle(color: colorScheme.onSurface, fontSize: 12),
                      );
                    }).toList(),
                    getTooltipColor: (_) => colorScheme.surfaceContainerHigh,
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < values.length; i++)
                        FlSpot(i.toDouble(), values[i]),
                    ],
                    color: accent,
                    barWidth: 2,
                    isCurved: false,
                    dotData: FlDotData(show: dates.length == 1),
                    belowBarData: BarAreaData(
                      show: true,
                      color: accent.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              fontWeight: AppTheme.headingWeight,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: AppTheme.emphasisWeight,
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
    super.key,
    required this.onTap,
    required this.color,
    required this.category,
    required this.amount,
    required this.percentage,
    required this.progress,
  });

  final Color color;
  final String category;
  final String amount;
  final String percentage;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
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
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: progress.clamp(0, 1),
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.12),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: AppTheme.headingWeight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsFilterPanel extends StatelessWidget {
  const _StatsFilterPanel({
    required this.ledger,
    required this.transactionType,
    required this.timeFilter,
    required this.onLedgerTap,
    required this.onTypeChanged,
    required this.onTimeChanged,
    required this.calendarMonth,
    required this.customRange,
    required this.onMonthChanged,
    required this.onCustomChanged,
    required this.onReset,
  });

  final Ledger ledger;
  final int transactionType;
  final TimeFilter timeFilter;
  final VoidCallback onLedgerTap;
  final ValueChanged<int> onTypeChanged;
  final ValueChanged<TimeFilter> onTimeChanged;
  final DateTime calendarMonth;
  final TransactionDateRange? customRange;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<TransactionDateRange> onCustomChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onLedgerTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ledger.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: AppTheme.emphasisWeight),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ResponsiveControls(
            first: _StatsControlGroup(
              label: '收支类型',
              child: SegmentedButton<int>(
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
                selected: {transactionType},
                onSelectionChanged: (selection) =>
                    onTypeChanged(selection.first),
              ),
            ),
            second: _StatsControlGroup(
              label: '时间范围',
              child: _TimeFilterChips(
                selected: timeFilter,
                monthIsCurrent:
                    calendarMonth.year == DateTime.now().year &&
                    calendarMonth.month == DateTime.now().month,
                onChanged: onTimeChanged,
              ),
            ),
          ),
          TransactionDateControls(
            month: calendarMonth,
            customRange: timeFilter == TimeFilter.custom ? customRange : null,
            onMonthChanged: onMonthChanged,
            onCustomChanged: onCustomChanged,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  timeFilter == TimeFilter.custom
                      ? (customRange?.label ?? '本月')
                      : timeFilter == TimeFilter.all
                      ? '全部时间'
                      : timeFilter == TimeFilter.week
                      ? '近7天（含今天）'
                      : timeFilter == TimeFilter.year
                      ? '本年（全年）'
                      : '所选月份（整月）',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: onReset, child: const Text('重置筛选')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsControlGroup extends StatelessWidget {
  const _StatsControlGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: AppTheme.headingWeight,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _TimeFilterChips extends StatelessWidget {
  const _TimeFilterChips({
    required this.selected,
    required this.onChanged,
    this.monthIsCurrent = true,
  });

  final TimeFilter selected;
  final bool monthIsCurrent;
  final ValueChanged<TimeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (TimeFilter.week, '近7天'),
      (TimeFilter.month, '本月'),
      (TimeFilter.year, '本年'),
      (TimeFilter.all, '全部'),
    ];

    return Row(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: ChoiceChip(
              showCheckmark: false,
              labelPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              label: Center(
                child: Text(
                  items[index].$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              selected:
                  selected == items[index].$1 &&
                  (selected != TimeFilter.month || monthIsCurrent),
              onSelected: (_) => onChanged(items[index].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _LedgerPickerTile extends StatelessWidget {
  const _LedgerPickerTile({
    required this.ledger,
    required this.selected,
    required this.onTap,
  });

  final Ledger ledger;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.62)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.menu_book_outlined,
                color: selected ? colorScheme.primary : colorScheme.onSurface,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ledger.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: AppTheme.emphasisWeight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
            children: [first, const SizedBox(height: 12), second],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
