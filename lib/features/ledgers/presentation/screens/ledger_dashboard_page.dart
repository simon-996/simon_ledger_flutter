import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import '../../../../core/common/gallery_launcher.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/person_transaction_stats.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../transactions/presentation/widgets/transaction_detail_sheet.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../widgets/share_ledger_image_widget.dart';

class LedgerDashboardPage extends ConsumerStatefulWidget {
  const LedgerDashboardPage({super.key, required this.ledger});

  final Ledger ledger;

  @override
  ConsumerState<LedgerDashboardPage> createState() =>
      _LedgerDashboardPageState();
}

class _LedgerDashboardPageState extends ConsumerState<LedgerDashboardPage> {
  bool _isSelectionMode = false;
  final Set<String> _selectedTransactionUuids = {};
  final Set<String> _selectedFilterPersonUuids = {};
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isGeneratingImage = false;
  String _displayCurrency = 'CNY';

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

  Future<void> _shareSelected(
    List<TransactionRecord> allTransactions,
    List<Person> peoplePool,
  ) async {
    if (_selectedTransactionUuids.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一条明细')));
      return;
    }

    setState(() {
      _isGeneratingImage = true;
    });

    try {
      final selectedTransactions = allTransactions
          .where((t) => _selectedTransactionUuids.contains(t.uuid))
          .toList();

      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final pixelRatio = devicePixelRatio.clamp(1.0, 2.0).toDouble();

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final request = await Gal.requestAccess();
        if (!request) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('需要相册权限才能保存图片')));
            setState(() {
              _isGeneratingImage = false;
            });
          }
          return;
        }
      }

      const maxTransactionsPerImage = 25;
      final pageCount = (selectedTransactions.length / maxTransactionsPerImage)
          .ceil()
          .clamp(1, 9999);
      final total = selectedTransactions.length;
      final base = total ~/ pageCount;
      final remainder = total % pageCount;

      final pages = <List<TransactionRecord>>[];
      var start = 0;
      for (var i = 0; i < pageCount; i++) {
        final size = base + (i < remainder ? 1 : 0);
        if (size <= 0) continue;
        pages.add(selectedTransactions.sublist(start, start + size));
        start += size;
      }

      if (!mounted) return;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < pages.length; i++) {
        if (!mounted) return;
        final imageBytes = await _screenshotController.captureFromLongWidget(
          ShareLedgerImageWidget(
            ledger: widget.ledger,
            transactions: pages[i],
            summaryTransactions: selectedTransactions,
            peoplePool: peoplePool,
            pageIndex: i + 1,
            totalPages: pages.length,
          ),
          context: context,
          pixelRatio: pixelRatio,
          constraints: const BoxConstraints(maxWidth: 400),
          delay: const Duration(milliseconds: 100),
        );

        await Gal.putImageBytes(
          imageBytes,
          name: 'SimonLedger_${nowMs}_p${i + 1}of${pages.length}',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pages.length > 1 ? '已保存 ${pages.length} 张到相册' : '长图已保存到相册',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: '打开相册',
              onPressed: () async {
                try {
                  await GalleryLauncher.openGalleryApp();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        FriendlyError.message(e, fallback: '无法打开相册，请手动查看。'),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        );
        _toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FriendlyError.message(e, fallback: '生成长图失败，请稍后重试。')),
          ),
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
    final transactionsAsyncValue = ref.watch(
      transactionNotifierProvider(widget.ledger.uuid),
    );
    final peopleAsyncValue = ref.watch(
      personNotifierProvider(
        includeDeleted: true,
        ledgerUuid: widget.ledger.uuid,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text(
                '已选择 ${_selectedTransactionUuids.length} 项',
                overflow: TextOverflow.ellipsis,
              )
            : _LedgerAppBarTitle(ledger: widget.ledger),
        leading: _isSelectionMode
            ? IconButton(
                tooltip: '退出选择',
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  tooltip: '全选',
                  icon: const Icon(Icons.select_all),
                  onPressed: () {
                    transactionsAsyncValue.whenData((transactions) {
                      setState(() {
                        if (_selectedTransactionUuids.length ==
                            transactions.length) {
                          _selectedTransactionUuids.clear();
                        } else {
                          _selectedTransactionUuids.addAll(
                            transactions.map((t) => t.uuid),
                          );
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
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : IconButton(
                            tooltip: '保存长图',
                            icon: const Icon(Icons.share),
                            onPressed: () =>
                                _shareSelected(transactions, peoplePool),
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
                  tooltip: '选择并分享',
                  icon: const Icon(Icons.share),
                  onPressed: _toggleSelectionMode,
                ),
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(
                      transactionNotifierProvider(widget.ledger.uuid),
                    );
                  },
                ),
              ],
      ),
      body: transactionsAsyncValue.when(
        loading: () => const AppLoadingState(
          title: '正在加载流水',
          message: '同步本地缓存和云端明细',
          icon: Icons.receipt_long_outlined,
        ),
        error: (err, stack) => AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: '加载流水失败',
          message: FriendlyError.message(err, fallback: '暂时无法加载流水，请检查网络后重试。'),
        ),
        data: (transactions) {
          final displayCurrencies = supportedCurrenciesForLedger(widget.ledger);
          if (!displayCurrencies.contains(_displayCurrency)) {
            _displayCurrency = 'CNY';
          }
          final totalExpense = transactions
              .where((t) => t.type == 0)
              .fold(
                0.0,
                (sum, t) =>
                    sum +
                    transactionAmountForDisplay(
                      t,
                      widget.ledger,
                      _displayCurrency,
                    ),
              );
          final totalIncome = transactions
              .where((t) => t.type == 1)
              .fold(
                0.0,
                (sum, t) =>
                    sum +
                    transactionAmountForDisplay(
                      t,
                      widget.ledger,
                      _displayCurrency,
                    ),
              );
          final balance = totalIncome - totalExpense;

          final personStats = calculatePersonTransactionStats(
            transactions,
            amountOf: (transaction) => transactionAmountForDisplay(
              transaction,
              widget.ledger,
              _displayCurrency,
            ),
          );
          final personBalances = personStats.personBalances;

          final colorScheme = Theme.of(context).colorScheme;

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
                    padding: const EdgeInsets.all(20),
                    color: colorScheme.primaryContainer.withValues(alpha: 0.42),
                    borderColor: colorScheme.primary.withValues(alpha: 0.12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '结余 ($_displayCurrency)',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (displayCurrencies.length > 1) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: displayCurrencies
                                  .map(
                                    (currency) => ButtonSegment(
                                      value: currency,
                                      label: Text(currency),
                                    ),
                                  )
                                  .toList(),
                              selected: {_displayCurrency},
                              onSelectionChanged: (selection) {
                                setState(
                                  () => _displayCurrency = selection.first,
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatMoney(_displayCurrency, balance),
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: AppMetricTile(
                                icon: Icons.arrow_downward_rounded,
                                label: '总收入',
                                value: formatMoney(
                                  _displayCurrency,
                                  totalIncome,
                                ),
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AppMetricTile(
                                icon: Icons.arrow_upward_rounded,
                                label: '总支出',
                                value: formatMoney(
                                  _displayCurrency,
                                  totalExpense,
                                ),
                                color: colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: peopleAsyncValue.when(
                  loading: () => const AppLoadingState(
                    title: '正在加载人员',
                    message: '准备账本人员和结余数据',
                    icon: Icons.group_outlined,
                  ),
                  error: (e, st) => AppEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: '加载人员失败',
                    message: FriendlyError.message(
                      e,
                      fallback: '暂时无法加载账本人员，请稍后重试。',
                    ),
                  ),
                  data: (peoplePool) {
                    final personMap = peopleByUuid(peoplePool);
                    final filteredTransactions = List<TransactionRecord>.from(
                      _selectedFilterPersonUuids.isEmpty
                          ? transactions
                          : transactions.where(
                              (t) => t.personUuids.any(
                                (pid) =>
                                    _selectedFilterPersonUuids.contains(pid),
                              ),
                            ),
                    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    final peopleInLedger = personBalances.keys.map((pid) {
                      return personOrFallback(personMap, pid);
                    }).toList();

                    return CustomScrollView(
                      slivers: [
                        if (peopleInLedger.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    2,
                                    16,
                                    10,
                                  ),
                                  child: AppSectionHeader(
                                    title: '人员结余',
                                    trailing: _selectedFilterPersonUuids.isEmpty
                                        ? null
                                        : TextButton(
                                            onPressed: () {
                                              setState(
                                                _selectedFilterPersonUuids
                                                    .clear,
                                              );
                                            },
                                            child: const Text('清除筛选'),
                                          ),
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
                                              90 + (index < 6 ? index : 6) * 35,
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
                                          isSelected: _selectedFilterPersonUuids
                                              .contains(p.uuid),
                                          onTap: () =>
                                              _toggleFilterSelection(p.uuid),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                if (personStats.settlements.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
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
                                          ...personStats.settlements
                                              .take(5)
                                              .map((settlement) {
                                                final from = personOrFallback(
                                                  personMap,
                                                  settlement.fromPersonUuid,
                                                );
                                                final to = personOrFallback(
                                                  personMap,
                                                  settlement.toPersonUuid,
                                                );
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
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
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: AppSectionHeader(
                              title: '流水明细',
                              trailing: Text(
                                '${filteredTransactions.length} 条',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        if (filteredTransactions.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: AppEmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: _selectedFilterPersonUuids.isEmpty
                                  ? '暂无记账流水'
                                  : '没有匹配的流水',
                              message: _selectedFilterPersonUuids.isEmpty
                                  ? '保存一条记账后，这里会显示明细。'
                                  : '切换人员筛选后再查看。',
                            ),
                          )
                        else
                          SliverList.builder(
                            itemCount: filteredTransactions.length,
                            itemBuilder: (context, index) {
                              final t = filteredTransactions[index];
                              final dateStr =
                                  '${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')} ${t.createdAt.hour.toString().padLeft(2, '0')}:${t.createdAt.minute.toString().padLeft(2, '0')}';
                              final peopleStr = avatarsForPeople(
                                personMap,
                                t.personUuids,
                              );
                              final selected =
                                  _isSelectionMode &&
                                  _selectedTransactionUuids.contains(t.uuid);

                              final delayMs = (index < 8 ? index : 8) * 28;
                              return AppAnimatedEntry(
                                delay: Duration(milliseconds: delayMs),
                                child: AppTransactionTile(
                                  selected: selected,
                                  leading: _isSelectionMode
                                      ? Checkbox(
                                          value: selected,
                                          onChanged: (_) =>
                                              _toggleSelection(t.uuid),
                                        )
                                      : null,
                                  category: t.category,
                                  date: dateStr,
                                  people: peopleStr,
                                  note: t.note,
                                  createdByText: t.createdByNickname,
                                  createdByAvatar: t.createdByAvatar,
                                  amount: formatTransactionPrimaryAmount(t),
                                  convertedAmount:
                                      formatTransactionConvertedAmount(
                                        t,
                                        widget.ledger,
                                      ),
                                  isExpense: t.type == 0,
                                  syncStatus: _syncStatusFor(t),
                                  syncError: t.syncError,
                                  onLongPress: () {
                                    if (!_isSelectionMode) {
                                      _toggleSelectionMode();
                                      _toggleSelection(t.uuid);
                                    }
                                  },
                                  onTap: () {
                                    if (_isSelectionMode) {
                                      _toggleSelection(t.uuid);
                                      return;
                                    }
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) =>
                                          TransactionDetailSheet(
                                            transaction: t,
                                            peoplePool: peoplePool,
                                            ledger: widget.ledger,
                                          ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
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

class _LedgerAppBarTitle extends StatelessWidget {
  const _LedgerAppBarTitle({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ledger.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge,
        ),
        Text(
          ledger.displayCode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
