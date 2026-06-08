import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import '../../../../core/common/gallery_launcher.dart';
import '../../../../core/common/image_saver.dart';
import '../../../../core/di/providers.dart';
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
import '../providers/ledger_stats_provider.dart';
import '../widgets/share_ledger_image_widget.dart';

enum _DetailTransactionTypeFilter { all, expense, income }

enum _DetailTimeFilter { all, week, month, year }

enum _DetailSyncFilter { all, pending, failed }

class LedgerDashboardPage extends ConsumerStatefulWidget {
  const LedgerDashboardPage({super.key, required this.ledger});

  final Ledger ledger;

  @override
  ConsumerState<LedgerDashboardPage> createState() =>
      _LedgerDashboardPageState();
}

class _LedgerDashboardPageState extends ConsumerState<LedgerDashboardPage> {
  final Set<String> _selectedFilterPersonUuids = {};
  final TextEditingController _searchController = TextEditingController();
  final ScreenshotController _screenshotController = ScreenshotController();
  _DetailTransactionTypeFilter _typeFilter = _DetailTransactionTypeFilter.all;
  _DetailTimeFilter _timeFilter = _DetailTimeFilter.all;
  _DetailSyncFilter _syncFilter = _DetailSyncFilter.all;
  String? _categoryFilter;
  bool _isGeneratingImage = false;
  String _displayCurrency = 'CNY';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentSyncPending());
  }

  Future<void> _silentSyncPending() async {
    try {
      final changed = await ref.read(syncCoordinatorProvider).syncAllPending();
      if (!changed || !mounted) return;
      ref.invalidate(transactionNotifierProvider(widget.ledger.uuid));
      ref.invalidate(
        personNotifierProvider(
          includeDeleted: true,
          ledgerUuid: widget.ledger.uuid,
        ),
      );
      ref.invalidate(ledgerStatsProvider);
      ref.invalidate(syncOverviewProvider);
    } catch (_) {
      // Silent retry: local content stays available while offline.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _showShareOptions(
    List<TransactionRecord> allTransactions,
    List<Person> peoplePool,
  ) async {
    final transactions = _visibleTransactions(allTransactions);
    final includeTransactions = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('分享账本', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                _selectedFilterPersonUuids.isEmpty
                    ? '选择导出的图片内容'
                    : '当前已按人员筛选，将按当前筛选结果导出',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _ShareOptionTile(
                icon: Icons.account_balance_wallet_outlined,
                title: '只分享账本概览',
                subtitle: '包含结余、收入支出和人员结算',
                onTap: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 10),
              _ShareOptionTile(
                icon: Icons.receipt_long_outlined,
                title: '分享概览和流水',
                subtitle: transactions.isEmpty
                    ? '当前没有流水，会导出空明细状态'
                    : '包含当前 ${transactions.length} 条流水明细',
                onTap: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );

    if (includeTransactions == null || !mounted) {
      return;
    }

    await _exportLedgerImage(
      transactions: transactions,
      peoplePool: peoplePool,
      includeTransactions: includeTransactions,
    );
  }

  Future<void> _exportLedgerImage({
    required List<TransactionRecord> transactions,
    required List<Person> peoplePool,
    required bool includeTransactions,
  }) async {
    setState(() {
      _isGeneratingImage = true;
    });

    try {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final pixelRatio = devicePixelRatio.clamp(1.0, 2.0).toDouble();

      final hasAccess = await ImageSaver.ensureAccess();
      if (!hasAccess) {
        if (mounted) {
          AppNotice.error(context, '需要相册权限才能保存图片');
          setState(() {
            _isGeneratingImage = false;
          });
        }
        return;
      }

      const exportImageWidth = 400.0;
      const maxTransactionsPerImage = 18;
      final pageCount = includeTransactions
          ? (transactions.length / maxTransactionsPerImage).ceil().clamp(
              1,
              9999,
            )
          : 1;
      final total = transactions.length;
      final base = total ~/ pageCount;
      final remainder = total % pageCount;

      final pages = <List<TransactionRecord>>[];
      if (includeTransactions) {
        var start = 0;
        for (var i = 0; i < pageCount; i++) {
          final size = base + (i < remainder ? 1 : 0);
          pages.add(
            size <= 0 ? const [] : transactions.sublist(start, start + size),
          );
          start += size;
        }
      } else {
        pages.add(const []);
      }

      if (!mounted) return;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      String? firstImageName;
      for (var i = 0; i < pages.length; i++) {
        if (!mounted) return;
        final imageBytes = await _screenshotController.captureFromLongWidget(
          ShareLedgerImageWidget(
            ledger: widget.ledger,
            transactions: pages[i],
            summaryTransactions: transactions,
            peoplePool: peoplePool,
            includeTransactions: includeTransactions,
            pageIndex: includeTransactions ? i + 1 : null,
            totalPages: includeTransactions ? pages.length : null,
          ),
          context: context,
          pixelRatio: pixelRatio,
          constraints: const BoxConstraints.tightFor(width: exportImageWidth),
          delay: const Duration(milliseconds: 100),
        );

        final imageName = 'SimonLedger_${nowMs}_p${i + 1}of${pages.length}';
        firstImageName ??= imageName;
        await ImageSaver.saveImageBytes(imageBytes, name: imageName);
      }

      if (mounted) {
        AppNotice.success(
          context,
          ImageSaver.canOpenSavedImage
              ? (pages.length > 1 ? '已保存 ${pages.length} 张到相册' : '长图已保存到相册')
              : (pages.length > 1 ? '已下载 ${pages.length} 张分享图片' : '分享图片已下载'),
          actionLabel: ImageSaver.canOpenSavedImage ? '打开相册' : null,
          onAction: ImageSaver.canOpenSavedImage
              ? () async {
                  try {
                    if (firstImageName != null) {
                      await GalleryLauncher.openImageByName(firstImageName);
                    } else {
                      await GalleryLauncher.openGalleryApp();
                    }
                  } catch (e) {
                    if (!mounted) return;
                    AppNotice.error(
                      context,
                      FriendlyError.message(e, fallback: '无法打开相册，请手动查看。'),
                    );
                  }
                }
              : null,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotice.error(
          context,
          FriendlyError.message(e, fallback: '生成长图失败，请稍后重试。'),
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
        title: _LedgerAppBarTitle(ledger: widget.ledger),
        actions: [
          peopleAsyncValue.when(
            data: (peoplePool) => transactionsAsyncValue.when(
              data: (transactions) => _isGeneratingImage
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: '分享账本图片',
                      icon: const Icon(Icons.share),
                      onPressed: () =>
                          _showShareOptions(transactions, peoplePool),
                    ),
              loading: () => const SizedBox(),
              error: (err, st) => const SizedBox(),
            ),
            loading: () => const SizedBox(),
            error: (err, st) => const SizedBox(),
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(transactionNotifierProvider(widget.ledger.uuid));
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
          final filteredTransactions = _visibleTransactions(transactions);
          final totalExpense = filteredTransactions
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
          final totalIncome = filteredTransactions
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
            filteredTransactions,
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
                    final peopleInLedger = _dashboardPersonIds(
                      transactions,
                    ).map((pid) => personOrFallback(personMap, pid)).toList();

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
                                    trailing: SizedBox(
                                      height: 32,
                                      child: AnimatedSwitcher(
                                        duration: AppMotion.fast,
                                        child:
                                            _selectedFilterPersonUuids.isEmpty
                                            ? const SizedBox(
                                                key: ValueKey(
                                                  'empty-filter-action',
                                                ),
                                                width: 1,
                                              )
                                            : TextButton(
                                                key: const ValueKey(
                                                  'clear-filter-action',
                                                ),
                                                style: TextButton.styleFrom(
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                ),
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
                                          name: p.isDeleted
                                              ? '${p.name}（已删除）'
                                              : p.name,
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
                                                    fromName: from.isDeleted
                                                        ? '${from.name}（已删除）'
                                                        : from.name,
                                                    toAvatar: to.avatar,
                                                    toName: to.isDeleted
                                                        ? '${to.name}（已删除）'
                                                        : to.name,
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
                          child: _TransactionFilterToolbar(
                            searchController: _searchController,
                            activeCount: _activeFilterCount,
                            onSearchChanged: (_) => setState(() {}),
                            onClear: _hasActiveFilters
                                ? _clearTransactionFilters
                                : null,
                            onFilterTap: () =>
                                _showTransactionFilterSheet(transactions),
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

                              final delayMs = (index < 8 ? index : 8) * 28;
                              return AppAnimatedEntry(
                                delay: Duration(milliseconds: delayMs),
                                child: AppTransactionTile(
                                  selected: false,
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
                                  onLongPress: null,
                                  onTap: () {
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

  List<TransactionRecord> _visibleTransactions(
    List<TransactionRecord> transactions,
  ) {
    final keyword = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    return List<TransactionRecord>.from(
      transactions.where((transaction) {
        if (!_matchesPersonFilter(transaction)) return false;
        if (!_matchesTypeFilter(transaction)) return false;
        if (!_matchesTimeFilter(transaction, now)) return false;
        if (!_matchesCategoryFilter(transaction)) return false;
        if (!_matchesSyncFilter(transaction)) return false;
        if (!_matchesKeyword(transaction, keyword)) return false;
        return true;
      }),
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  bool _matchesPersonFilter(TransactionRecord transaction) {
    if (_selectedFilterPersonUuids.isEmpty) return true;
    return transaction.personUuids.any(_selectedFilterPersonUuids.contains) ||
        (transaction.payerPersonUuid != null &&
            _selectedFilterPersonUuids.contains(transaction.payerPersonUuid));
  }

  bool _matchesTypeFilter(TransactionRecord transaction) {
    return switch (_typeFilter) {
      _DetailTransactionTypeFilter.all => true,
      _DetailTransactionTypeFilter.expense => transaction.type == 0,
      _DetailTransactionTypeFilter.income => transaction.type == 1,
    };
  }

  bool _matchesTimeFilter(TransactionRecord transaction, DateTime now) {
    return switch (_timeFilter) {
      _DetailTimeFilter.all => true,
      _DetailTimeFilter.week =>
        now.difference(transaction.createdAt).inDays <= 7,
      _DetailTimeFilter.month =>
        transaction.createdAt.year == now.year &&
            transaction.createdAt.month == now.month,
      _DetailTimeFilter.year => transaction.createdAt.year == now.year,
    };
  }

  bool _matchesCategoryFilter(TransactionRecord transaction) {
    final category = _categoryFilter;
    if (category == null || category.isEmpty) return true;
    return transaction.category == category;
  }

  bool _matchesSyncFilter(TransactionRecord transaction) {
    return switch (_syncFilter) {
      _DetailSyncFilter.all => true,
      _DetailSyncFilter.pending => transaction.pendingSync,
      _DetailSyncFilter.failed =>
        transaction.pendingSync &&
            transaction.syncError != null &&
            transaction.syncError!.isNotEmpty,
    };
  }

  bool _matchesKeyword(TransactionRecord transaction, String keyword) {
    if (keyword.isEmpty) return true;
    return transaction.category.toLowerCase().contains(keyword) ||
        transaction.note.toLowerCase().contains(keyword) ||
        (transaction.createdByNickname ?? '').toLowerCase().contains(keyword);
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedFilterPersonUuids.isNotEmpty) count += 1;
    if (_searchController.text.trim().isNotEmpty) count += 1;
    if (_typeFilter != _DetailTransactionTypeFilter.all) count += 1;
    if (_timeFilter != _DetailTimeFilter.all) count += 1;
    if (_categoryFilter != null) count += 1;
    if (_syncFilter != _DetailSyncFilter.all) count += 1;
    return count;
  }

  bool get _hasActiveFilters => _activeFilterCount > 0;

  void _clearTransactionFilters() {
    setState(() {
      _selectedFilterPersonUuids.clear();
      _searchController.clear();
      _typeFilter = _DetailTransactionTypeFilter.all;
      _timeFilter = _DetailTimeFilter.all;
      _categoryFilter = null;
      _syncFilter = _DetailSyncFilter.all;
    });
  }

  Future<void> _showTransactionFilterSheet(
    List<TransactionRecord> transactions,
  ) async {
    final selection = await showModalBottomSheet<_TransactionFilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _TransactionFilterSheet(
        typeFilter: _typeFilter,
        timeFilter: _timeFilter,
        categoryFilter: _categoryFilter,
        syncFilter: _syncFilter,
        categories: _availableCategories(transactions),
      ),
    );
    if (selection == null || !mounted) return;
    setState(() {
      _typeFilter = selection.typeFilter;
      _timeFilter = selection.timeFilter;
      _categoryFilter = selection.categoryFilter;
      _syncFilter = selection.syncFilter;
    });
  }

  List<String> _availableCategories(List<TransactionRecord> transactions) {
    return transactions
        .map((transaction) => transaction.category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _dashboardPersonIds(List<TransactionRecord> transactions) {
    final ids = <String>{
      ...widget.ledger.personUuids,
      for (final transaction in transactions) ...transaction.personUuids,
      for (final transaction in transactions)
        if (transaction.payerPersonUuid != null &&
            transaction.payerPersonUuid!.isNotEmpty)
          transaction.payerPersonUuid!,
    };
    return ids.toList();
  }
}

class _TransactionFilterToolbar extends StatelessWidget {
  const _TransactionFilterToolbar({
    required this.searchController,
    required this.activeCount,
    required this.onSearchChanged,
    required this.onFilterTap,
    required this.onClear,
  });

  final TextEditingController searchController;
  final int activeCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onFilterTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索分类、备注或添加人',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton.filledTonal(
                tooltip: '筛选流水',
                onPressed: onFilterTap,
                icon: const Icon(Icons.tune_rounded),
              ),
              if (activeCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      activeCount.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: '清除筛选',
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionFilterSelection {
  const _TransactionFilterSelection({
    required this.typeFilter,
    required this.timeFilter,
    required this.categoryFilter,
    required this.syncFilter,
  });

  final _DetailTransactionTypeFilter typeFilter;
  final _DetailTimeFilter timeFilter;
  final String? categoryFilter;
  final _DetailSyncFilter syncFilter;
}

class _TransactionFilterSheet extends StatefulWidget {
  const _TransactionFilterSheet({
    required this.typeFilter,
    required this.timeFilter,
    required this.categoryFilter,
    required this.syncFilter,
    required this.categories,
  });

  final _DetailTransactionTypeFilter typeFilter;
  final _DetailTimeFilter timeFilter;
  final String? categoryFilter;
  final _DetailSyncFilter syncFilter;
  final List<String> categories;

  @override
  State<_TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<_TransactionFilterSheet> {
  late _DetailTransactionTypeFilter _typeFilter;
  late _DetailTimeFilter _timeFilter;
  late String? _categoryFilter;
  late _DetailSyncFilter _syncFilter;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.typeFilter;
    _timeFilter = widget.timeFilter;
    _categoryFilter = widget.categoryFilter;
    _syncFilter = widget.syncFilter;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '筛选流水',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _FilterGroup(
              title: '收支类型',
              child: SegmentedButton<_DetailTransactionTypeFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _DetailTransactionTypeFilter.all,
                    label: Text('全部'),
                  ),
                  ButtonSegment(
                    value: _DetailTransactionTypeFilter.expense,
                    label: Text('支出'),
                  ),
                  ButtonSegment(
                    value: _DetailTransactionTypeFilter.income,
                    label: Text('收入'),
                  ),
                ],
                selected: {_typeFilter},
                onSelectionChanged: (values) {
                  setState(() => _typeFilter = values.single);
                },
              ),
            ),
            const SizedBox(height: 14),
            _FilterGroup(
              title: '时间范围',
              child: SegmentedButton<_DetailTimeFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _DetailTimeFilter.all,
                    label: Text('全部'),
                  ),
                  ButtonSegment(
                    value: _DetailTimeFilter.week,
                    label: Text('7 天'),
                  ),
                  ButtonSegment(
                    value: _DetailTimeFilter.month,
                    label: Text('本月'),
                  ),
                  ButtonSegment(
                    value: _DetailTimeFilter.year,
                    label: Text('本年'),
                  ),
                ],
                selected: {_timeFilter},
                onSelectionChanged: (values) {
                  setState(() => _timeFilter = values.single);
                },
              ),
            ),
            const SizedBox(height: 14),
            _FilterGroup(
              title: '同步状态',
              child: SegmentedButton<_DetailSyncFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _DetailSyncFilter.all,
                    label: Text('全部'),
                  ),
                  ButtonSegment(
                    value: _DetailSyncFilter.pending,
                    label: Text('待同步'),
                  ),
                  ButtonSegment(
                    value: _DetailSyncFilter.failed,
                    label: Text('失败'),
                  ),
                ],
                selected: {_syncFilter},
                onSelectionChanged: (values) {
                  setState(() => _syncFilter = values.single);
                },
              ),
            ),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 14),
              _FilterGroup(
                title: '分类',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: _categoryFilter == null,
                      onSelected: (_) => setState(() => _categoryFilter = null),
                    ),
                    for (final category in widget.categories)
                      FilterChip(
                        label: Text(category),
                        selected: _categoryFilter == category,
                        onSelected: (_) {
                          setState(() => _categoryFilter = category);
                        },
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('重置'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('应用筛选'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _reset() {
    setState(() {
      _typeFilter = _DetailTransactionTypeFilter.all;
      _timeFilter = _DetailTimeFilter.all;
      _categoryFilter = null;
      _syncFilter = _DetailSyncFilter.all;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _TransactionFilterSelection(
        typeFilter: _typeFilter,
        timeFilter: _timeFilter,
        categoryFilter: _categoryFilter,
        syncFilter: _syncFilter,
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
    );
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
