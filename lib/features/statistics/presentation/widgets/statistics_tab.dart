import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sliver_tools/sliver_tools.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
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
  int _transactionType = 0; // 0 for expense, 1 for income

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  @override
  void didUpdateWidget(covariant StatisticsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ledgers != oldWidget.ledgers) {
      if (_selectedLedgerUuid != null) {
        final exists = widget.ledgers.any((l) => l.uuid == _selectedLedgerUuid);
        if (!exists) {
          setState(() {
            _selectedLedgerUuid = widget.ledgers.isNotEmpty ? widget.ledgers.first.uuid : null;
          });
        }
      } else if (widget.ledgers.isNotEmpty) {
        setState(() {
          _selectedLedgerUuid = widget.ledgers.first.uuid;
        });
      }
    }
  }

  void _initDefaults() {
    if (widget.ledgers.isNotEmpty) {
      _selectedLedgerUuid = widget.ledgers.first.uuid;
    }
  }

  List<TransactionRecord> _filterTransactions(List<TransactionRecord> transactions) {
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

  Map<String, double> _aggregateByCategory(List<TransactionRecord> transactions) {
    final map = <String, double>{};
    for (final t in transactions) {
      map[t.category] = (map[t.category] ?? 0.0) + t.amount;
    }
    return map;
  }

  Color _getColorForCategory(int index, BuildContext context) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.error,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.cyan.shade400,
      Colors.indigo.shade400,
      Colors.lime.shade400,
      Colors.pink.shade400,
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ledgers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('请先在“账本”页面添加一个账本'),
          ],
        ),
      );
    }

    if (_selectedLedgerUuid == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentLedger = widget.ledgers.firstWhere(
      (l) => l.uuid == _selectedLedgerUuid,
      orElse: () => widget.ledgers.first,
    );

    final transactionsAsyncValue = ref.watch(transactionNotifierProvider(_selectedLedgerUuid!));
    final peopleAsyncValue = ref.watch(personNotifierProvider(includeDeleted: true));

    return Column(
      children: [
        // Header Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedLedgerUuid,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        prefixIcon: Icon(Icons.book),
                      ),
                      isExpanded: true,
                      items: widget.ledgers
                          .map((l) => DropdownMenuItem(value: l.uuid, child: Text(l.name)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedLedgerUuid = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('支出')),
                      ButtonSegment(value: 1, label: Text('收入')),
                    ],
                    selected: {_transactionType},
                    onSelectionChanged: (Set<int> newSelection) {
                      setState(() => _transactionType = newSelection.first);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<TimeFilter>(
                segments: const [
                  ButtonSegment(value: TimeFilter.week, label: Text('近7天')),
                  ButtonSegment(value: TimeFilter.month, label: Text('本月')),
                  ButtonSegment(value: TimeFilter.year, label: Text('本年')),
                  ButtonSegment(value: TimeFilter.all, label: Text('全部')),
                ],
                selected: {_timeFilter},
                onSelectionChanged: (Set<TimeFilter> newSelection) {
                  setState(() => _timeFilter = newSelection.first);
                },
              ),
            ],
          ),
        ),

        // Body
        Expanded(
          child: transactionsAsyncValue.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (allTransactions) {
              final filtered = _filterTransactions(allTransactions);
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pie_chart_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      const Text('该时间段内没有记录'),
                    ],
                  ),
                );
              }

              final categoryMap = _aggregateByCategory(filtered);
              final sortedCategories = categoryMap.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              
              final totalAmount = sortedCategories.fold(0.0, (sum, item) => sum + item.value);

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Text(
                            '总${_transactionType == 0 ? "支出" : "收入"}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${currentLedger.baseCurrencyCode} ${totalAmount.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _transactionType == 0 
                                      ? Theme.of(context).colorScheme.error 
                                      : Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            height: 200,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 40,
                                sections: List.generate(sortedCategories.length, (i) {
                                  final isTouched = false;
                                  final radius = isTouched ? 60.0 : 50.0;
                                  final entry = sortedCategories[i];
                                  final percentage = (entry.value / totalAmount * 100).toStringAsFixed(1);
                                  
                                  return PieChartSectionData(
                                    color: _getColorForCategory(i, context),
                                    value: entry.value,
                                    title: '$percentage%',
                                    radius: radius,
                                    titleStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('分类占比', style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),

                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = sortedCategories[index];
                        final percentage = (entry.value / totalAmount * 100).toStringAsFixed(1);
                        return ListTile(
                          leading: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: _getColorForCategory(index, context),
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(entry.key),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${currentLedger.baseCurrencyCode} ${entry.value.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('$percentage%', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        );
                      },
                      childCount: sortedCategories.length,
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text('明细记录', style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),

                  peopleAsyncValue.when(
                    loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
                    error: (e, st) => SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
                    data: (peoplePool) {
                      final sortedTransactions = List<TransactionRecord>.from(filtered)
                        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                      
                      final Map<String, double> personBalances = {};
                      for (final t in sortedTransactions) {
                        if (t.personUuids.isEmpty) continue;
                        final splitAmount = t.amount / t.personUuids.length;
                        for (final pid in t.personUuids) {
                          personBalances[pid] ??= 0.0;
                          if (t.type == 0) {
                            personBalances[pid] = personBalances[pid]! - splitAmount;
                          } else {
                            personBalances[pid] = personBalances[pid]! + splitAmount;
                          }
                        }
                      }

                      final peopleInLedger = personBalances.keys.map((pid) {
                        return peoplePool.firstWhere(
                          (p) => p.uuid == pid, 
                          orElse: () => Person()..uuid = pid..name = '未知'..avatar = '👤'
                        );
                      }).toList();

                      return MultiSliver(
                        children: [
                          if (peopleInLedger.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: Text('人员结余', style: Theme.of(context).textTheme.titleMedium),
                                  ),
                                  SizedBox(
                                    height: 100,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      itemCount: peopleInLedger.length,
                                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                                      itemBuilder: (context, index) {
                                        final p = peopleInLedger[index];
                                        final pBalance = personBalances[p.uuid] ?? 0.0;
                                        
                                        return Container(
                                          width: 80,
                                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.surface,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Theme.of(context).colorScheme.outlineVariant,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(p.avatar, style: const TextStyle(fontSize: 24)),
                                              const SizedBox(height: 4),
                                              Expanded(
                                                child: Text(
                                                  p.name, 
                                                  style: const TextStyle(fontSize: 12),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  '${pBalance >= 0 ? '+' : ''}${pBalance.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: pBalance >= 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final t = sortedTransactions[index];
                                final dateStr = '${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')} ${t.createdAt.hour.toString().padLeft(2, '0')}:${t.createdAt.minute.toString().padLeft(2, '0')}';
                                
                                final peopleStr = t.personUuids.map((pid) {
                                  return peoplePool.firstWhere((p) => p.uuid == pid, orElse: () => Person()..uuid = ''..name = '?').avatar;
                                }).join('');

                                return ListTile(
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
                                  title: Row(
                                    children: [
                                      Text(t.category, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Text(peopleStr, style: const TextStyle(fontSize: 14)),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(dateStr),
                                      if (t.note.isNotEmpty) Text(t.note, style: const TextStyle(fontStyle: FontStyle.italic)),
                                    ],
                                  ),
                                  trailing: Text(
                                    '${t.type == 0 ? '-' : '+'} ${t.currencyCode} ${t.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: t.type == 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                );
                              },
                              childCount: sortedTransactions.length,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}