import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../transactions/presentation/widgets/transaction_detail_sheet.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../widgets/share_ledger_image_widget.dart';

class LedgerDashboardPage extends ConsumerStatefulWidget {
  const LedgerDashboardPage({super.key, required this.ledger});

  final Ledger ledger;

  @override
  ConsumerState<LedgerDashboardPage> createState() => _LedgerDashboardPageState();
}

class _LedgerDashboardPageState extends ConsumerState<LedgerDashboardPage> {
  bool _isSelectionMode = false;
  final Set<String> _selectedTransactionUuids = {};
  final Set<String> _selectedFilterPersonUuids = {};
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isGeneratingImage = false;

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedTransactionUuids.clear();
    });
  }

  void _toggleSelection(String uuid) {
    setState(() {
      if (_selectedTransactionUuids.contains(uuid)) {
        _selectedTransactionUuids.remove(uuid);
      } else {
        _selectedTransactionUuids.add(uuid);
      }
    });
  }

  void _toggleFilterSelection(String uuid) {
    setState(() {
      if (_selectedFilterPersonUuids.contains(uuid)) {
        _selectedFilterPersonUuids.remove(uuid);
      } else {
        _selectedFilterPersonUuids.add(uuid);
      }
    });
  }

  Future<void> _shareSelected(List<TransactionRecord> allTransactions, List<Person> peoplePool) async {
    if (_selectedTransactionUuids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一条明细')),
      );
      return;
    }

    setState(() {
      _isGeneratingImage = true;
    });

    try {
      final selectedTransactions = allTransactions
          .where((t) => _selectedTransactionUuids.contains(t.uuid))
          .toList();

      final imageBytes = await _screenshotController.captureFromWidget(
        MediaQuery(
          data: MediaQuery.of(context),
          child: Directionality(
            textDirection: Directionality.of(context),
            child: Material(
              child: ShareLedgerImageWidget(
                ledger: widget.ledger,
                transactions: selectedTransactions,
                peoplePool: peoplePool,
              ),
            ),
          ),
        ),
        delay: const Duration(milliseconds: 100),
      );

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final request = await Gal.requestAccess();
        if (!request) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要相册权限才能保存图片')),
            );
            setState(() {
              _isGeneratingImage = false;
            });
          }
          return;
        }
      }

      await Gal.putImageBytes(imageBytes, name: 'SimonLedger_${DateTime.now().millisecondsSinceEpoch}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('长图已保存到相册')),
        );
        _toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成长图失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsyncValue = ref.watch(transactionNotifierProvider(widget.ledger.uuid));
    final peopleAsyncValue = ref.watch(personNotifierProvider(includeDeleted: true));

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '已选择 ${_selectedTransactionUuids.length} 项' : widget.ledger.name),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: () {
                    transactionsAsyncValue.whenData((transactions) {
                      setState(() {
                        if (_selectedTransactionUuids.length == transactions.length) {
                          _selectedTransactionUuids.clear();
                        } else {
                          _selectedTransactionUuids.addAll(transactions.map((t) => t.uuid));
                        }
                      });
                    });
                  },
                ),
                peopleAsyncValue.when(
                  data: (peoplePool) => transactionsAsyncValue.when(
                    data: (transactions) => _isGeneratingImage
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                          )
                        : IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () => _shareSelected(transactions, peoplePool),
                          ),
                    loading: () => const SizedBox(),
                    error: (err, st) => const SizedBox(),
                  ),
                  loading: () => const SizedBox(),
                  error: (err, st) => const SizedBox(),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _toggleSelectionMode,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(transactionNotifierProvider(widget.ledger.uuid));
                  },
                ),
              ],
      ),
      body: transactionsAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (transactions) {
          final totalExpense = transactions.where((t) => t.type == 0).fold(0.0, (sum, t) => sum + t.amount);
          final totalIncome = transactions.where((t) => t.type == 1).fold(0.0, (sum, t) => sum + t.amount);
          final balance = totalIncome - totalExpense;

          final Map<String, double> personBalances = {};
          for (final t in transactions) {
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

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '结余 (${widget.ledger.baseCurrencyCode})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        balance.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.arrow_downward, size: 16, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text('总收入', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    totalIncome.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.arrow_upward, size: 16, color: Theme.of(context).colorScheme.error),
                                    const SizedBox(width: 4),
                                    Text('总支出', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    totalExpense.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              
              Expanded(
                child: peopleAsyncValue.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Center(child: Text('Error: $e')),
                  data: (peoplePool) {
                    final filteredTransactions = _selectedFilterPersonUuids.isEmpty
                        ? transactions
                        : transactions.where((t) => t.personUuids.any((pid) => _selectedFilterPersonUuids.contains(pid))).toList();

                    final peopleInLedger = personBalances.keys.map((pid) {
                      return peoplePool.firstWhere(
                        (p) => p.uuid == pid, 
                        orElse: () => Person()..uuid = pid..name = '未知'..avatar = '👤'
                      );
                    }).toList();

                    return Column(
                      children: [
                        if (peopleInLedger.isNotEmpty) ...[
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
                                final isSelected = _selectedFilterPersonUuids.contains(p.uuid);
                                
                                return GestureDetector(
                                  onTap: () => _toggleFilterSelection(p.uuid),
                                  child: Container(
                                    width: 80,
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                                        width: isSelected ? 2 : 1,
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
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        
                        Expanded(
                          child: filteredTransactions.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.outline),
                                      const SizedBox(height: 16),
                                      Text(_selectedFilterPersonUuids.isEmpty ? '暂无记账流水' : '没有匹配的流水'),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filteredTransactions.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final t = filteredTransactions[index];
                                    final dateStr = '${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')} ${t.createdAt.hour.toString().padLeft(2, '0')}:${t.createdAt.minute.toString().padLeft(2, '0')}';
                                    
                                    final peopleStr = t.personUuids.map((pid) {
                                      return peoplePool.firstWhere((p) => p.uuid == pid, orElse: () => Person()..uuid = ''..name = '?').avatar;
                                    }).join('');

                                    return ListTile(
                                      selected: _isSelectionMode && _selectedTransactionUuids.contains(t.uuid),
                                      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                                      onLongPress: () {
                                        if (!_isSelectionMode) {
                                          _toggleSelectionMode();
                                          _toggleSelection(t.uuid);
                                        }
                                      },
                                      onTap: () {
                                        if (_isSelectionMode) {
                                          _toggleSelection(t.uuid);
                                        } else {
                                          showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (context) => TransactionDetailSheet(
                                              transaction: t,
                                              peoplePool: peoplePool,
                                              ledger: widget.ledger,
                                            ),
                                          );
                                        }
                                      },
                                      leading: _isSelectionMode
                                          ? Checkbox(
                                              value: _selectedTransactionUuids.contains(t.uuid),
                                              onChanged: (_) => _toggleSelection(t.uuid),
                                            )
                                          : null,
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
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
