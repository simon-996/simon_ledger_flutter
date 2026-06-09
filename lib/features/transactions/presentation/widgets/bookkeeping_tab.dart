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
import '../../../../core/preferences/transaction_category_preference.dart';
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
  final _amountFocusNode = FocusNode();

  List<String> _expenseCategories =
      TransactionCategoryPreference.defaultExpenseCategories;
  List<String> _incomeCategories =
      TransactionCategoryPreference.defaultIncomeCategories;

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
    for (final ledger in _recordableLedgers) {
      if (ledger.uuid == uuid) return ledger;
    }
    return null;
  }

  List<Ledger> get _recordableLedgers {
    return widget.ledgers
        .where((ledger) => ledger.canRecordTransactions)
        .toList();
  }

  Future<void> _initDefaults() async {
    final categories = await TransactionCategoryPreference.read();
    final draft = await BookkeepingDraftPreference.read();
    final lastUuid = await LastSelectedLedgerPreference.getUuid();
    final ledgers = _recordableLedgers;

    if (!mounted) return;

    setState(() {
      _expenseCategories = categories.expense;
      _incomeCategories = categories.income;
      if (ledgers.isEmpty) return;

      if (draft != null &&
          ledgers.any((ledger) => ledger.uuid == draft.ledgerUuid)) {
        _transactionType = draft.transactionType == 1 ? 1 : 0;
        _selectedCategory = _categoryOrDefault(draft.category);
        _selectedCurrency = draft.currencyCode;
        _selectedPersonIds
          ..clear()
          ..addAll(draft.personUuids);
        _payerPersonUuid = draft.payerPersonUuid;
        _updateSelectedLedger(draft.ledgerUuid, persist: false);
      } else if (lastUuid != null &&
          ledgers.any((ledger) => ledger.uuid == lastUuid)) {
        _selectedCategory ??= _currentCategories.first;
        _updateSelectedLedger(lastUuid, persist: false);
      } else if (ledgers.length == 1) {
        _selectedCategory ??= _currentCategories.first;
        _updateSelectedLedger(ledgers.first.uuid, persist: false);
      } else {
        _selectedCategory ??= _currentCategories.first;
        _selectedLedgerUuid = null;
      }
    });
    if (ledgers.isEmpty) return;
    _persistDraft();
  }

  void _updateSelectedLedger(String ledgerUuid, {bool persist = true}) {
    _selectedLedgerUuid = ledgerUuid;
    final ledger = _recordableLedgers.firstWhere((l) => l.uuid == ledgerUuid);
    _sanitizeCurrentSelection(ledger);

    LastSelectedLedgerPreference.setUuid(ledgerUuid);
    if (persist) {
      _persistDraft();
    }
  }

  List<String> get _currentCategories {
    return _transactionType == 0 ? _expenseCategories : _incomeCategories;
  }

  Future<void> _addCurrentCategory() async {
    final transactionType = _transactionType;
    final category = await showTransactionCategoryCreateSheet(
      context: context,
      categories: _currentCategories,
      isIncome: transactionType == 1,
    );
    if (category == null) return;

    final categories = await TransactionCategoryPreference.addCategory(
      transactionType: transactionType,
      category: category,
    );
    if (!mounted) return;
    setState(() {
      _expenseCategories = categories.expense;
      _incomeCategories = categories.income;
      if (_transactionType == transactionType) {
        _selectedCategory = category;
      }
    });
    _persistDraft();
    AppNotice.success(context, '已添加分类');
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
    _amountFocusNode.dispose();
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
      await _rememberCategory(_transactionType, category);
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

  Future<void> _rememberCategory(int transactionType, String category) async {
    try {
      final categories = await TransactionCategoryPreference.markRecentlyUsed(
        transactionType: transactionType,
        category: category,
      );
      if (!mounted) return;
      setState(() {
        _expenseCategories = categories.expense;
        _incomeCategories = categories.income;
      });
    } catch (_) {
      // Recent category order is a convenience cache; it must not affect saving.
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordableLedgers = _recordableLedgers;
    if (recordableLedgers.isEmpty) {
      return AppEmptyState(
        icon: Icons.edit_note_rounded,
        title: widget.ledgers.isEmpty ? '还没有可记账的账本' : '当前没有可记账的账本',
        message: widget.ledgers.isEmpty
            ? '先到“账本”页面创建账本，再回来记录收支。'
            : '你对现有共享账本只有查看权限，可以联系管理员调整权限，或创建自己的账本。',
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
    final ledgerPeopleById = ref
        .watch(cachedPeopleProvider)
        .maybeWhen(data: peopleByUuid, orElse: () => const <String, Person>{});
    final syncStatus = selectedLedger == null
        ? null
        : ref.watch(ledgerSyncStatusProvider(selectedLedger.uuid)).valueOrNull;
    return AnimatedTheme(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      data: _bookkeepingAccentTheme(context),
      child: Builder(
        builder: (context) {
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
                          ledgers: recordableLedgers,
                          ledger: selectedLedger,
                          peopleById: ledgerPeopleById,
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
                        child: _BookkeepingAmountPanel(
                          selectedType: _transactionType,
                          onTypeChanged: (type) {
                            _setAndPersist(() {
                              _transactionType = type;
                              if (_transactionType == 1) {
                                _payerPersonUuid = null;
                              }
                              _selectedCategory = _currentCategories.first;
                            });
                          },
                          amountController: _amountController,
                          amountFocusNode: _amountFocusNode,
                          selectedCurrency: _selectedCurrency ?? 'CNY',
                          currencies: currencyOptions,
                          onCurrencyChanged: (currency) {
                            _setAndPersist(() => _selectedCurrency = currency);
                          },
                          onAmountChanged: _limitAmountPrecision,
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
                                  key: ValueKey(
                                    'category-header-$_transactionType',
                                  ),
                                  title: '分类',
                                  trailing: Icon(
                                    _transactionType == 0
                                        ? Icons.trending_down_rounded
                                        : Icons.trending_up_rounded,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              CategorySelector(
                                categories: _currentCategories,
                                selectedCategory:
                                    _selectedCategory ??
                                    _currentCategories.first,
                                isIncome: _transactionType == 1,
                                onChanged: (category) {
                                  _setAndPersist(
                                    () => _selectedCategory = category,
                                  );
                                },
                                onAddCategory: _addCurrentCategory,
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
                                FriendlyError.message(
                                  e,
                                  fallback: '人员加载失败，请稍后重试。',
                                ),
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
                                  key: ValueKey(
                                    'people-${selectedLedger.uuid}',
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TransactionAnimatedVisibility(
                                        visible: _transactionType == 0,
                                        visibleKey: 'payment-mode-panel',
                                        hiddenKey: 'payment-mode-empty',
                                        child: Padding(
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
                                                      ? _selectedPersonIds.first
                                                      : activePersonIds.first;
                                                } else {
                                                  _payerPersonUuid = null;
                                                }
                                              });
                                            },
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
                                      TransactionAnimatedVisibility(
                                        visible:
                                            _transactionType == 0 &&
                                            _payerPersonUuid != null,
                                        visibleKey: 'payer-person-panel',
                                        hiddenKey: 'payer-person-empty',
                                        child: Padding(
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
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
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
                                                        _payerPersonUuid = pid;
                                                      });
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
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
                    bottom: 12,
                  ),
                  child: AppAnimatedSwitcher(
                    child: peopleAsyncValue.maybeWhen(
                      data: (peoplePool) => TransactionSaveButton(
                        key: const ValueKey('save-enabled'),
                        onPressed:
                            _selectedLedgerUuid == null || _savingTransaction
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
        },
      ),
    );
  }

  ThemeData _bookkeepingAccentTheme(BuildContext context) {
    final baseTheme = Theme.of(context);
    final baseScheme = baseTheme.colorScheme;
    final accent = transactionAccentColor(baseScheme, _transactionType);
    final onAccent = transactionOnAccentColor(baseScheme, _transactionType);
    final colorScheme = baseScheme.copyWith(
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: Color.alphaBlend(
        accent.withValues(alpha: 0.14),
        baseScheme.surfaceContainerLowest,
      ),
      onPrimaryContainer: accent,
    );
    final disabledBackground = baseScheme.surfaceContainerHighest;
    final disabledForeground = baseScheme.onSurfaceVariant;
    final filledButtonStyle =
        baseTheme.filledButtonTheme.style ?? const ButtonStyle();
    final textButtonStyle =
        baseTheme.textButtonTheme.style ?? const ButtonStyle();
    final outlinedButtonStyle =
        baseTheme.outlinedButtonTheme.style ?? const ButtonStyle();

    return baseTheme.copyWith(
      colorScheme: colorScheme,
      filledButtonTheme: FilledButtonThemeData(
        style: filledButtonStyle.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledBackground;
            }
            return accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledForeground;
            }
            return onAccent;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: textButtonStyle.copyWith(
          foregroundColor: WidgetStateProperty.all(accent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: outlinedButtonStyle.copyWith(
          foregroundColor: WidgetStateProperty.all(accent),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: baseScheme.outlineVariant);
            }
            return BorderSide(color: accent);
          }),
        ),
      ),
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

class _BookkeepingAmountPanel extends StatelessWidget {
  const _BookkeepingAmountPanel({
    required this.selectedType,
    required this.onTypeChanged,
    required this.amountController,
    required this.amountFocusNode,
    required this.selectedCurrency,
    required this.currencies,
    required this.onCurrencyChanged,
    required this.onAmountChanged,
  });

  final int selectedType;
  final ValueChanged<int> onTypeChanged;
  final TextEditingController amountController;
  final FocusNode amountFocusNode;
  final String selectedCurrency;
  final List<String> currencies;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<String> onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      key: const ValueKey('bookkeeping-amount-panel'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TransactionTypeSelector(
              selectedType: selectedType,
              onChanged: onTypeChanged,
            ),
            const SizedBox(height: 16),
            TransactionResponsivePair(
              breakpoint: 0,
              first: SizedBox(
                height: 58,
                child: TextField(
                  key: const ValueKey('bookkeeping-amount-input'),
                  controller: amountController,
                  focusNode: amountFocusNode,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    labelText: '金额',
                    hintText: '0.00',
                    hintStyle: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.58,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                    prefixText: '$selectedCurrency ',
                    prefixStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  onChanged: onAmountChanged,
                ),
              ),
              second: CurrencySelector(
                currencies: currencies,
                selectedCurrency: selectedCurrency,
                onChanged: onCurrencyChanged,
              ),
            ),
          ],
        ),
      ),
    );
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
    final toneColor = transactionAccentColor(colorScheme, transactionType);
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
    required this.peopleById,
    required this.currencyCode,
    required this.isIncome,
    required this.onLedgerChanged,
  });

  final List<Ledger> ledgers;
  final Ledger? ledger;
  final Map<String, Person> peopleById;
  final String? currencyCode;
  final bool isIncome;
  final ValueChanged<String> onLedgerChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isIncome ? AppTheme.incomeColor : AppTheme.expenseColor;
    final mutedColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.68);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showLedgerPicker(context),
        child: AppSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: colorScheme.surfaceContainerLow.withValues(alpha: 0.46),
          borderColor: colorScheme.outlineVariant.withValues(alpha: 0.46),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isIncome
                      ? Icons.savings_outlined
                      : Icons.receipt_long_outlined,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ledger?.name ?? '点击选择一个账本',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: ledger == null
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurface,
                        fontWeight: ledger == null
                            ? FontWeight.w600
                            : FontWeight.w800,
                      ),
                    ),
                    if (ledger != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${currencyCode ?? 'CNY'} · ${ledger!.displayCode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: mutedColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
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
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _LedgerPickerSheet(
        ledgers: ledgers,
        selectedLedgerUuid: ledger?.uuid,
        peopleById: peopleById,
      ),
    );

    if (picked != null) {
      onLedgerChanged(picked);
    }
  }
}

class _LedgerPickerSheet extends StatefulWidget {
  const _LedgerPickerSheet({
    required this.ledgers,
    required this.selectedLedgerUuid,
    required this.peopleById,
  });

  final List<Ledger> ledgers;
  final String? selectedLedgerUuid;
  final Map<String, Person> peopleById;

  @override
  State<_LedgerPickerSheet> createState() => _LedgerPickerSheetState();
}

class _LedgerPickerSheetState extends State<_LedgerPickerSheet> {
  final _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleLedgers = _keyword.isEmpty
        ? widget.ledgers
        : widget.ledgers.where(_matchesKeyword).toList();

    return FractionallySizedBox(
      heightFactor: 0.78,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择所属账本',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${visibleLedgers.length}/${widget.ledgers.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _LedgerPickerSearchField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _keyword = value.trim().toLowerCase());
                },
                onClear: () {
                  _searchController.clear();
                  setState(() => _keyword = '');
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visibleLedgers.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.search_off_rounded,
                        title: '没有找到匹配账本',
                        message: '换个账本名称试试。',
                      )
                    : ListView.separated(
                        clipBehavior: Clip.hardEdge,
                        itemCount: visibleLedgers.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = visibleLedgers[index];
                          final selected =
                              item.uuid == widget.selectedLedgerUuid;
                          return _LedgerPickerItem(
                            ledger: item,
                            peopleById: widget.peopleById,
                            selected: selected,
                            onTap: () => Navigator.of(context).pop(item.uuid),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _matchesKeyword(Ledger ledger) {
    final keyword = _keyword;
    if (keyword.isEmpty) return true;
    return ledger.name.trim().toLowerCase().contains(keyword) ||
        ledger.displayCode.toLowerCase().contains(keyword) ||
        ledger.baseCurrencyCode.toLowerCase().contains(keyword);
  }
}

class _LedgerPickerSearchField extends StatelessWidget {
  const _LedgerPickerSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索账本名称',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
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
    );
  }
}

class _LedgerPickerItem extends StatelessWidget {
  const _LedgerPickerItem({
    required this.ledger,
    required this.peopleById,
    required this.selected,
    required this.onTap,
  });

  final Ledger ledger;
  final Map<String, Person> peopleById;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metadataStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      fontWeight: FontWeight.w500,
    );
    final localManualPeople = ledger.personUuids
        .map((uuid) => personOrFallback(peopleById, uuid, name: '人员'))
        .where((person) => person.linkedUserUuid == null && !person.isDeleted)
        .toList();
    final hasPeople = ledger.members.isNotEmpty || localManualPeople.isNotEmpty;
    final backgroundColor = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.76)
        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.88);
    final borderColor = selected
        ? colorScheme.primary.withValues(alpha: 0.72)
        : colorScheme.outlineVariant.withValues(alpha: 0.92);

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: selected ? 1.3 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(width: 8),
                    _LedgerMetaChip(
                      icon: Icons.currency_exchange_rounded,
                      label: ledger.baseCurrencyCode,
                    ),
                    if (ledger.isShared) ...[
                      const SizedBox(width: 6),
                      _LedgerMetaChip(
                        icon: Icons.group_outlined,
                        label: '${ledger.memberCount} 人共享',
                      ),
                    ],
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
                const SizedBox(height: 3),
                Text(
                  ledger.displayCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metadataStyle,
                ),
                if (hasPeople) ...[
                  const SizedBox(height: 8),
                  AppLedgerPeopleChips(
                    sharedMembers: ledger.members,
                    localManualPeople: localManualPeople,
                    peopleById: peopleById,
                    singleLine: true,
                  ),
                ],
              ],
            ),
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
