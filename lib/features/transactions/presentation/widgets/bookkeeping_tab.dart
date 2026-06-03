import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/preferences/bookkeeping_preference.dart';
import '../../../../core/preferences/last_selected_ledger_preference.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../providers/transaction_provider.dart';
import 'transaction_form_components.dart';

class BookkeepingTab extends ConsumerStatefulWidget {
  const BookkeepingTab({super.key, required this.ledgers});

  final List<Ledger> ledgers;

  @override
  ConsumerState<BookkeepingTab> createState() => _BookkeepingTabState();
}

class _BookkeepingTabState extends ConsumerState<BookkeepingTab> {
  String? _selectedLedgerUuid;
  String? _selectedCategory;
  final Set<String> _selectedPersonIds = {};
  String? _selectedCurrency;
  String? _payerPersonUuid;
  int _transactionType = 0;
  bool _savingTransaction = false;
  bool _successDialogVisible = false;

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  final List<String> _expenseCategories = [
    '默认',
    '交通',
    '购物',
    '餐饮',
    '杂费',
    '娱乐',
    '居住',
  ];
  final List<String> _incomeCategories = ['默认', '工资', '兼职', '理财', '红包', '其他'];

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  @override
  void didUpdateWidget(covariant BookkeepingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ledgers == oldWidget.ledgers || _selectedLedgerUuid == null) {
      return;
    }

    final currentLedger = _selectedLedger;
    if (currentLedger == null) {
      setState(() {
        _selectedLedgerUuid = null;
        _selectedCurrency = null;
        _payerPersonUuid = null;
        _selectedPersonIds.clear();
      });
      return;
    }

    setState(() {
      _sanitizeCurrentSelection(currentLedger);
    });
    _persistDraft();
  }

  Ledger? get _selectedLedger {
    final uuid = _selectedLedgerUuid;
    if (uuid == null) return null;
    for (final ledger in widget.ledgers) {
      if (ledger.uuid == uuid) return ledger;
    }
    return null;
  }

  Future<void> _initDefaults() async {
    final draft = await BookkeepingDraftPreference.read();
    final lastUuid = await LastSelectedLedgerPreference.getUuid();

    if (!mounted || widget.ledgers.isEmpty) return;

    setState(() {
      if (draft != null &&
          widget.ledgers.any((ledger) => ledger.uuid == draft.ledgerUuid)) {
        _transactionType = draft.transactionType == 1 ? 1 : 0;
        _selectedCategory = _categoryOrDefault(draft.category);
        _selectedCurrency = draft.currencyCode;
        _selectedPersonIds
          ..clear()
          ..addAll(draft.personUuids);
        _payerPersonUuid = draft.payerPersonUuid;
        _updateSelectedLedger(draft.ledgerUuid, persist: false);
      } else if (lastUuid != null &&
          widget.ledgers.any((l) => l.uuid == lastUuid)) {
        _selectedCategory ??= _currentCategories.first;
        _updateSelectedLedger(lastUuid, persist: false);
      } else if (widget.ledgers.length == 1) {
        _selectedCategory ??= _currentCategories.first;
        _updateSelectedLedger(widget.ledgers.first.uuid, persist: false);
      } else {
        _selectedCategory ??= _currentCategories.first;
        _selectedLedgerUuid = null;
      }
    });
    _persistDraft();
  }

  void _updateSelectedLedger(String ledgerUuid, {bool persist = true}) {
    _selectedLedgerUuid = ledgerUuid;
    final ledger = widget.ledgers.firstWhere((l) => l.uuid == ledgerUuid);
    _sanitizeCurrentSelection(ledger);

    LastSelectedLedgerPreference.setUuid(ledgerUuid);
    if (persist) {
      _persistDraft();
    }
  }

  List<String> get _currentCategories {
    return _transactionType == 0 ? _expenseCategories : _incomeCategories;
  }

  String _categoryOrDefault(String? category) {
    final value = category?.trim();
    if (value != null && _currentCategories.contains(value)) {
      return value;
    }
    return _currentCategories.first;
  }

  void _sanitizeCurrentSelection(Ledger ledger) {
    final currencies = supportedCurrenciesForLedger(ledger);
    _selectedCurrency = currencies.contains(_selectedCurrency)
        ? _selectedCurrency
        : currencies.last;
    _selectedCategory = _categoryOrDefault(_selectedCategory);
    if (_transactionType == 1) {
      _payerPersonUuid = null;
    } else if (!ledger.personUuids.contains(_payerPersonUuid)) {
      _payerPersonUuid = null;
    }
    _selectedPersonIds.retainWhere(ledger.personUuids.contains);
    if (_selectedPersonIds.isEmpty && ledger.personUuids.isNotEmpty) {
      _selectedPersonIds.add(ledger.personUuids.first);
    }
    if (ledger.personUuids.isEmpty) {
      _selectedPersonIds.clear();
      _payerPersonUuid = null;
    }
  }

  void _setAndPersist(VoidCallback update) {
    setState(update);
    _persistDraft();
  }

  void _persistDraft() {
    final ledgerUuid = _selectedLedgerUuid;
    if (ledgerUuid == null) return;
    BookkeepingDraftPreference.write(
      BookkeepingDraft(
        ledgerUuid: ledgerUuid,
        transactionType: _transactionType,
        category: _selectedCategory ?? _currentCategories.first,
        currencyCode: _selectedCurrency ?? 'CNY',
        personUuids: _selectedPersonIds.toList(),
        payerPersonUuid: _transactionType == 0 ? _payerPersonUuid : null,
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _showSuccessAnimation(
    double amount,
    String currency,
    String category,
    String ledgerName,
    int transactionType,
    Iterable<Person> people,
  ) {
    _successDialogVisible = true;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: _BookkeepingSuccessCard(
            amount: amount,
            currency: currency,
            category: category,
            ledgerName: ledgerName,
            transactionType: transactionType,
            people: people.toList(),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: Curves.easeInCubic,
        );
        final scale = Tween<double>(begin: 0.94, end: 1).animate(curved);
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offset,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
    ).whenComplete(() {
      _successDialogVisible = false;
    });

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || !_successDialogVisible) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      if (!navigator.canPop()) return;
      _successDialogVisible = false;
      navigator.pop();
    });
  }

  void _saveTransaction(List<Person> peoplePool) async {
    if (_savingTransaction) return;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      AppNotice.error(context, '请输入大于 0 的有效金额');
      return;
    }

    if (_selectedPersonIds.isEmpty) {
      AppNotice.error(context, '请至少选择一个参与人员');
      return;
    }

    final category = _selectedCategory ?? '默认';
    final currency = _selectedCurrency ?? 'CNY';
    final ledgerId = _selectedLedgerUuid;
    final ledger = _selectedLedger;

    if (ledgerId == null) {
      AppNotice.error(context, '请先选择一个所属账本');
      return;
    }

    final personMap = peopleByUuid(peoplePool);
    final selectedPeople = _selectedPersonIds
        .map((pid) => personOrFallback(personMap, pid))
        .toList();
    setState(() => _savingTransaction = true);
    try {
      final profile = await ref.read(localProfileProvider.future);
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final record = TransactionRecord()
        ..uuid = DateTime.now().microsecondsSinceEpoch.toString()
        ..ledgerUuid = ledgerId
        ..type = _transactionType
        ..payerPersonUuid = _transactionType == 0 ? _payerPersonUuid : null
        ..amount = amount
        ..currencyCode = currency
        ..category = category
        ..personUuids = _selectedPersonIds.toList()
        ..note = _noteController.text.trim()
        ..createdByUserUuid = currentUser?.uuid
        ..createdByNickname =
            currentUser?.nickname ?? profile.normalizedNickname
        ..createdByAvatar = currentUser?.avatar ?? profile.personAvatar
        ..createdAt = DateTime.now();

      await ref
          .read(transactionNotifierProvider(ledgerId).notifier)
          .addTransaction(record);
    } catch (e) {
      if (!mounted) return;
      AppNotice.error(
        context,
        FriendlyError.message(e, fallback: '保存失败，请稍后重试。'),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _savingTransaction = false);
      }
    }

    if (mounted) {
      _showSuccessAnimation(
        amount,
        currency,
        category,
        ledger?.name ?? '当前账本',
        _transactionType,
        selectedPeople,
      );
      _amountController.clear();
      _noteController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ledgers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.edit_note_rounded,
        title: '还没有可记账的账本',
        message: '先到“账本”页面创建账本，再回来记录收支。',
      );
    }

    final selectedLedger = _selectedLedger;
    final currencyOptions = selectedLedger == null
        ? const ['CNY']
        : supportedCurrenciesForLedger(selectedLedger);
    if (!currencyOptions.contains(_selectedCurrency)) {
      _selectedCurrency = currencyOptions.last;
    }
    final peopleAsyncValue = ref.watch(
      personNotifierProvider(
        includeDeleted: false,
        ledgerUuid: selectedLedger?.uuid,
      ),
    );
    final syncStatus = selectedLedger == null
        ? null
        : ref.watch(ledgerSyncStatusProvider(selectedLedger.uuid)).valueOrNull;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pagePadding,
              AppTheme.pagePadding,
              AppTheme.pagePadding,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppAnimatedEntry(
                  child: _QuickEntryHeader(
                    key: ValueKey(
                      'quick-header-${selectedLedger?.uuid}-$_transactionType',
                    ),
                    ledgers: widget.ledgers,
                    ledger: selectedLedger,
                    currencyCode: _selectedCurrency,
                    isIncome: _transactionType == 1,
                    onLedgerChanged: (ledgerUuid) {
                      setState(() {
                        _updateSelectedLedger(ledgerUuid);
                      });
                    },
                  ),
                ),
                if (syncStatus?.hasPending == true) ...[
                  const SizedBox(height: 10),
                  _BookkeepingSyncBanner(status: syncStatus!),
                ],
                const SizedBox(height: 14),
                AppAnimatedEntry(
                  delay: const Duration(milliseconds: 60),
                  child: AppSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TransactionTypeSelector(
                          selectedType: _transactionType,
                          onChanged: (type) {
                            _setAndPersist(() {
                              _transactionType = type;
                              if (_transactionType == 1) {
                                _payerPersonUuid = null;
                              }
                              _selectedCategory = _currentCategories.first;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        TransactionResponsivePair(
                          breakpoint: 0,
                          first: SizedBox(
                            height: 56,
                            child: TextField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                              decoration: InputDecoration(
                                labelText: '金额',
                                hintText: '0.00',
                                hintStyle: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.62),
                                      fontWeight: FontWeight.w700,
                                    ),
                                prefixText: '${_selectedCurrency ?? 'CNY'} ',
                                prefixStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              onChanged: _limitAmountPrecision,
                            ),
                          ),
                          second: CurrencySelector(
                            currencies: currencyOptions,
                            selectedCurrency: _selectedCurrency ?? 'CNY',
                            onChanged: (currency) {
                              _setAndPersist(
                                () => _selectedCurrency = currency,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AppAnimatedEntry(
                  delay: const Duration(milliseconds: 120),
                  child: AppSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppAnimatedSwitcher(
                          child: AppSectionHeader(
                            key: ValueKey('category-header-$_transactionType'),
                            title: '分类',
                            trailing: Icon(
                              _transactionType == 0
                                  ? Icons.trending_down_rounded
                                  : Icons.trending_up_rounded,
                              color: _transactionType == 0
                                  ? colorScheme.error
                                  : colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        CategorySelector(
                          categories: _currentCategories,
                          selectedCategory:
                              _selectedCategory ?? _currentCategories.first,
                          isIncome: _transactionType == 1,
                          onChanged: (category) {
                            _setAndPersist(() => _selectedCategory = category);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (selectedLedger != null)
                  AppAnimatedEntry(
                    delay: const Duration(milliseconds: 180),
                    child: peopleAsyncValue.when(
                      loading: () => const AppSectionCard(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, st) => AppSectionCard(
                        child: Text(
                          FriendlyError.message(e, fallback: '人员加载失败，请稍后重试。'),
                        ),
                      ),
                      data: (peoplePool) {
                        if (selectedLedger.personUuids.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        final personMap = peopleByUuid(peoplePool);
                        final activePersonIds = selectedLedger.personUuids
                            .where(personMap.containsKey)
                            .toList();
                        if (activePersonIds.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        _sanitizeVisiblePeopleSelection(activePersonIds);
                        final personChoices = activePersonIds.map((pid) {
                          final person = personMap[pid]!;
                          return AppPersonChoiceItem(
                            id: pid,
                            name: person.name,
                            avatar: person.avatar,
                          );
                        }).toList();
                        return AppAnimatedSwitcher(
                          child: AppSectionCard(
                            key: ValueKey('people-${selectedLedger.uuid}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AnimatedSize(
                                  duration: AppMotion.normal,
                                  curve: AppMotion.emphasized,
                                  alignment: Alignment.topCenter,
                                  child: AnimatedSwitcher(
                                    duration: AppMotion.normal,
                                    switchInCurve: AppMotion.emphasized,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder:
                                        transactionTopFadeSizeTransition,
                                    child: _transactionType == 0
                                        ? Padding(
                                            key: const ValueKey(
                                              'payment-mode-panel',
                                            ),
                                            padding: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            child: PaymentModePanel(
                                              paidByPerson:
                                                  _payerPersonUuid != null,
                                              description:
                                                  _payerPersonUuid == null
                                                  ? '使用人员将平均分摊该支出金额。'
                                                  : '付款人先垫付，总额由使用人员平均分摊。',
                                              onChanged: (paidByPerson) {
                                                _setAndPersist(() {
                                                  if (paidByPerson) {
                                                    _payerPersonUuid ??=
                                                        _selectedPersonIds
                                                            .isNotEmpty
                                                        ? _selectedPersonIds
                                                              .first
                                                        : activePersonIds.first;
                                                  } else {
                                                    _payerPersonUuid = null;
                                                  }
                                                });
                                              },
                                            ),
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('payment-mode-empty'),
                                          ),
                                  ),
                                ),
                                AppSectionHeader(
                                  title: _transactionType == 0
                                      ? '使用人员'
                                      : '参与人员',
                                  trailing: TextButton(
                                    onPressed: () {
                                      _setAndPersist(() {
                                        if (_selectedPersonIds.length ==
                                            activePersonIds.length) {
                                          _selectedPersonIds.clear();
                                        } else {
                                          _selectedPersonIds.addAll(
                                            activePersonIds,
                                          );
                                        }
                                      });
                                    },
                                    child: Text(
                                      _selectedPersonIds.length ==
                                              activePersonIds.length
                                          ? '取消全选'
                                          : '全选',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AppPersonChoiceGrid(
                                  items: personChoices,
                                  selectedIds: _selectedPersonIds,
                                  onToggle: (pid, selected) {
                                    _setAndPersist(() {
                                      if (selected) {
                                        _selectedPersonIds.add(pid);
                                      } else {
                                        _selectedPersonIds.remove(pid);
                                      }
                                    });
                                  },
                                ),
                                AnimatedSize(
                                  duration: AppMotion.normal,
                                  curve: AppMotion.emphasized,
                                  alignment: Alignment.topCenter,
                                  child: AnimatedSwitcher(
                                    duration: AppMotion.normal,
                                    switchInCurve: AppMotion.emphasized,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder:
                                        transactionTopFadeSizeTransition,
                                    child:
                                        _transactionType == 0 &&
                                            _payerPersonUuid != null
                                        ? Padding(
                                            key: const ValueKey(
                                              'payer-person-panel',
                                            ),
                                            padding: const EdgeInsets.only(
                                              top: 16,
                                            ),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: colorScheme
                                                    .surfaceContainerLow,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: colorScheme
                                                      .outlineVariant
                                                      .withValues(alpha: 0.72),
                                                ),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Text(
                                                      '付款人',
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.titleSmall,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    AppPersonChoiceGrid(
                                                      items: personChoices,
                                                      selectedId:
                                                          _payerPersonUuid,
                                                      onSelect: (pid) {
                                                        _setAndPersist(() {
                                                          _payerPersonUuid =
                                                              pid;
                                                        });
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('payer-person-empty'),
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
                if (selectedLedger != null) const SizedBox(height: 14),
                AppAnimatedEntry(
                  delay: const Duration(milliseconds: 220),
                  child: TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: '备注（选填）',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 2,
                    minLines: 1,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: AppAnimatedSwitcher(
              child: peopleAsyncValue.maybeWhen(
                data: (peoplePool) => TransactionSaveButton(
                  key: const ValueKey('save-enabled'),
                  onPressed: _selectedLedgerUuid == null || _savingTransaction
                      ? null
                      : () => _saveTransaction(peoplePool),
                  loading: _savingTransaction,
                  readyLabel: '保存记账',
                  loadingLabel: '保存中',
                ),
                orElse: () => const TransactionSaveButton(
                  key: ValueKey('save-loading'),
                  onPressed: null,
                  loading: true,
                  readyLabel: '保存记账',
                  loadingLabel: '准备中',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _limitAmountPrecision(String value) {
    if (!value.contains('.')) return;
    final parts = value.split('.');
    if (parts.length <= 1 || parts[1].length <= 2) return;

    _amountController.text = '${parts[0]}.${parts[1].substring(0, 2)}';
    _amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: _amountController.text.length),
    );
  }

  void _sanitizeVisiblePeopleSelection(List<String> activePersonIds) {
    final activePersonIdSet = activePersonIds.toSet();
    var changed = false;

    final beforeCount = _selectedPersonIds.length;
    _selectedPersonIds.retainWhere(activePersonIdSet.contains);
    changed = changed || beforeCount != _selectedPersonIds.length;

    if (_selectedPersonIds.isEmpty) {
      _selectedPersonIds.add(activePersonIds.first);
      changed = true;
    }

    if (_payerPersonUuid != null &&
        !activePersonIdSet.contains(_payerPersonUuid)) {
      _payerPersonUuid = null;
      changed = true;
    }

    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _persistDraft();
      });
    }
  }
}

class _BookkeepingSuccessCard extends StatelessWidget {
  const _BookkeepingSuccessCard({
    required this.amount,
    required this.currency,
    required this.category,
    required this.ledgerName,
    required this.transactionType,
    required this.people,
  });

  final double amount;
  final String currency;
  final String category;
  final String ledgerName;
  final int transactionType;
  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIncome = transactionType == 1;
    final toneColor = isIncome ? colorScheme.primary : colorScheme.error;
    final amountPrefix = isIncome ? '+' : '-';
    final visiblePeople = people.take(3).toList();
    final hiddenPeopleCount = people.length - visiblePeople.length;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        elevation: 18,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SuccessCheckBadge(color: toneColor),
              const SizedBox(height: 16),
              Text(
                isIncome ? '收入已记下' : '支出已记下',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                '已保存到 $ledgerName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$amountPrefix $currency ${amount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: toneColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _SuccessInfoChip(
                    icon: Icons.category_outlined,
                    label: category,
                  ),
                  for (final person in visiblePeople)
                    _SuccessInfoChip(avatar: person.avatar, label: person.name),
                  if (hiddenPeopleCount > 0)
                    _SuccessInfoChip(label: '+$hiddenPeopleCount 人'),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '本机已保存，可以继续记账',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessCheckBadge extends StatelessWidget {
  const _SuccessCheckBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.16),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.check_rounded, size: 34, color: color),
          ),
        ),
      ),
    );
  }
}

class _SuccessInfoChip extends StatelessWidget {
  const _SuccessInfoChip({required this.label, this.icon, this.avatar});

  final String label;
  final IconData? icon;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarText = avatar;
    return Container(
      constraints: const BoxConstraints(maxWidth: 136),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
          ] else if (avatarText != null && avatarText.isNotEmpty) ...[
            Text(avatarText, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookkeepingSyncBanner extends StatelessWidget {
  const _BookkeepingSyncBanner({required this.status});

  final LedgerSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = status.hasFailed;
    final color = failed ? colorScheme.error : colorScheme.tertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.cloud_sync_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              failed
                  ? '部分数据同步失败，已保存在本机'
                  : '待同步 ${status.pendingCount} 项，联网后自动上传',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEntryHeader extends StatelessWidget {
  const _QuickEntryHeader({
    super.key,
    required this.ledgers,
    required this.ledger,
    required this.currencyCode,
    required this.isIncome,
    required this.onLedgerChanged,
  });

  final List<Ledger> ledgers;
  final Ledger? ledger;
  final String? currencyCode;
  final bool isIncome;
  final ValueChanged<String> onLedgerChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isIncome ? colorScheme.primary : colorScheme.error;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showLedgerPicker(context),
        child: AppSectionCard(
          padding: const EdgeInsets.all(18),
          color: colorScheme.primaryContainer.withValues(alpha: 0.38),
          borderColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isIncome
                      ? Icons.savings_outlined
                      : Icons.receipt_long_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ledger?.name ?? '点击选择一个账本',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (ledger != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${currencyCode ?? 'CNY'} · ${ledger!.displayCode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.expand_more_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLedgerPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: ledgers.length + 1,
          separatorBuilder: (context, index) => index == 0
              ? const SizedBox(height: 8)
              : const SizedBox(height: 6),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Text(
                '选择所属账本',
                style: Theme.of(context).textTheme.titleMedium,
              );
            }

            final item = ledgers[index - 1];
            final selected = item.uuid == ledger?.uuid;
            return _LedgerPickerItem(
              ledger: item,
              selected: selected,
              onTap: () => Navigator.of(context).pop(item.uuid),
            );
          },
        ),
      ),
    );

    if (picked != null) {
      onLedgerChanged(picked);
    }
  }
}

class _LedgerPickerItem extends StatelessWidget {
  const _LedgerPickerItem({
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
    final metadataStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      fontWeight: FontWeight.w500,
    );

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.58)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.primary.withValues(alpha: 0.14)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ledger.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_circle_rounded,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ledger.displayCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metadataStyle,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _LedgerMetaChip(
                          icon: Icons.currency_exchange_rounded,
                          label: ledger.baseCurrencyCode,
                        ),
                        if (ledger.isShared)
                          _LedgerMetaChip(
                            icon: Icons.group_outlined,
                            label: '${ledger.memberCount} 人共享',
                          )
                        else
                          const _LedgerMetaChip(
                            icon: Icons.person_outline_rounded,
                            label: '个人账本',
                          ),
                      ],
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

class _LedgerMetaChip extends StatelessWidget {
  const _LedgerMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
