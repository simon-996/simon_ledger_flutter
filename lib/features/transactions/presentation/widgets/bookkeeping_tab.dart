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
    Iterable<Person> people,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (context, animation, secondaryAnimation) {
        final colorScheme = Theme.of(context).colorScheme;

        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: FadeTransition(
              opacity: animation,
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 42,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '记账成功',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$currency ${amount.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Chip(
                        avatar: const Icon(Icons.category_outlined, size: 16),
                        label: Text(category),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: people
                            .map((p) => Text('${p.avatar} ${p.name}'))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _saveTransaction(List<Person> peoplePool) async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入大于 0 的有效金额')));
      return;
    }

    if (_selectedPersonIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个参与人员')));
      return;
    }

    final category = _selectedCategory ?? '默认';
    final currency = _selectedCurrency ?? 'CNY';
    final ledgerId = _selectedLedgerUuid;

    if (ledgerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择一个所属账本')));
      return;
    }

    final personMap = peopleByUuid(peoplePool);
    final selectedPeople = _selectedPersonIds.map((pid) {
      return personOrFallback(personMap, pid);
    }).toList();
    final profile = await ref.read(localProfileProvider.future);
    final currentUser = await ref.read(currentUserProvider.future);

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
      ..createdByNickname = currentUser?.nickname ?? profile.normalizedNickname
      ..createdByAvatar = currentUser?.avatar ?? profile.personAvatar
      ..createdAt = DateTime.now();

    try {
      await ref
          .read(transactionNotifierProvider(ledgerId).notifier)
          .addTransaction(record);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FriendlyError.message(e, fallback: '保存失败，请稍后重试。')),
        ),
      );
      return;
    }

    if (mounted) {
      _showSuccessAnimation(amount, currency, category, selectedPeople);
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
        includeDeleted: true,
        ledgerUuid: selectedLedger?.uuid,
      ),
    );
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
                const SizedBox(height: 14),
                AppAnimatedEntry(
                  delay: const Duration(milliseconds: 60),
                  child: AppSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TransactionTypeSelector(
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
                        _ResponsivePair(
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
                                prefixText: '${_selectedCurrency ?? 'CNY'} ',
                              ),
                              onChanged: _limitAmountPrecision,
                            ),
                          ),
                          second: _CurrencySelector(
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
                        _CategorySelector(
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
                        final personChoices = selectedLedger.personUuids.map((
                          pid,
                        ) {
                          final person = personOrFallback(personMap, pid);
                          return AppPersonChoiceItem(
                            id: pid,
                            name: person.name,
                            avatar: person.avatar,
                          );
                        }).toList();
                        return AppAnimatedSwitcher(
                          child: AppSectionCard(
                            key: ValueKey(
                              'people-${selectedLedger.uuid}-$_transactionType-${_payerPersonUuid != null}',
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_transactionType == 0) ...[
                                  SegmentedButton<bool>(
                                    showSelectedIcon: false,
                                    segments: const [
                                      ButtonSegment(
                                        value: false,
                                        icon: Icon(
                                          Icons.account_balance_wallet_outlined,
                                        ),
                                        label: Text('共同钱包'),
                                      ),
                                      ButtonSegment(
                                        value: true,
                                        icon: Icon(
                                          Icons.person_outline_rounded,
                                        ),
                                        label: Text('某人代付'),
                                      ),
                                    ],
                                    selected: {_payerPersonUuid != null},
                                    onSelectionChanged: (selection) {
                                      _setAndPersist(() {
                                        if (selection.first) {
                                          _payerPersonUuid ??=
                                              _selectedPersonIds.isNotEmpty
                                              ? _selectedPersonIds.first
                                              : selectedLedger
                                                    .personUuids
                                                    .first;
                                        } else {
                                          _payerPersonUuid = null;
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _payerPersonUuid == null
                                        ? '使用人员将平均分摊该支出金额。'
                                        : '付款人先垫付，总额由使用人员平均分摊。',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                AppSectionHeader(
                                  title: _transactionType == 0
                                      ? '使用人员'
                                      : '参与人员',
                                  trailing: TextButton(
                                    onPressed: () {
                                      _setAndPersist(() {
                                        if (_selectedPersonIds.length ==
                                            selectedLedger.personUuids.length) {
                                          _selectedPersonIds.clear();
                                        } else {
                                          _selectedPersonIds.addAll(
                                            selectedLedger.personUuids,
                                          );
                                        }
                                      });
                                    },
                                    child: Text(
                                      _selectedPersonIds.length ==
                                              selectedLedger.personUuids.length
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
                                if (_transactionType == 0 &&
                                    _payerPersonUuid != null) ...[
                                  const SizedBox(height: 16),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant
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
                                            selectedId: _payerPersonUuid,
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
                                ],
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
                data: (peoplePool) => FilledButton.icon(
                  key: const ValueKey('save-enabled'),
                  onPressed: _selectedLedgerUuid == null
                      ? null
                      : () => _saveTransaction(peoplePool),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('保存记账'),
                ),
                orElse: () => FilledButton.icon(
                  key: const ValueKey('save-loading'),
                  onPressed: null,
                  icon: const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  label: const Text('加载中'),
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

    return AppSectionCard(
      padding: const EdgeInsets.all(18),
      color: colorScheme.primaryContainer.withValues(alpha: 0.38),
      borderColor: colorScheme.primary.withValues(alpha: 0.12),
      child: _ResponsivePair(
        breakpoint: 0,
        first: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isIncome ? Icons.savings_outlined : Icons.receipt_long_outlined,
                color: accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('快速记账', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    ledger == null
                        ? '请选择账本'
                        : '${ledger!.name} · ${currencyCode ?? 'CNY'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (ledger != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      ledger!.displayCode,
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
          ],
        ),
        second: _LedgerSelector(
          ledgers: ledgers,
          selectedLedger: ledger,
          onChanged: onLedgerChanged,
        ),
      ),
    );
  }
}

class _LedgerSelector extends StatelessWidget {
  const _LedgerSelector({
    required this.ledgers,
    required this.selectedLedger,
    required this.onChanged,
  });

  final List<Ledger> ledgers;
  final Ledger? selectedLedger;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ledger = selectedLedger;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showLedgerPicker(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '所属账本',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ledger?.name ?? '请选择账本',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
          separatorBuilder: (_, index) => index == 0
              ? const SizedBox(height: 8)
              : const SizedBox(height: 6),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Text(
                '选择所属账本',
                style: Theme.of(context).textTheme.titleMedium,
              );
            }

            final ledger = ledgers[index - 1];
            final selected = ledger.uuid == selectedLedger?.uuid;
            return _LedgerPickerItem(
              ledger: ledger,
              selected: selected,
              onTap: () => Navigator.of(context).pop(ledger.uuid),
            );
          },
        ),
      ),
    );

    if (picked != null) {
      onChanged(picked);
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
                    Text(
                      ledger.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        ledger.displayCode,
                        ledger.baseCurrencyCode,
                        if (ledger.isShared) '${ledger.memberCount} 人共享',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: AppMotion.fast,
                child: Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionTypeSelector extends StatelessWidget {
  const _TransactionTypeSelector({
    required this.selectedType,
    required this.onChanged,
  });

  final int selectedType;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TransactionTypeButton(
            label: '支出',
            icon: Icons.remove_rounded,
            selected: selectedType == 0,
            value: 0,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TransactionTypeButton(
            label: '收入',
            icon: Icons.add_rounded,
            selected: selectedType == 1,
            value: 1,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TransactionTypeButton extends StatelessWidget {
  const _TransactionTypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = value == 0 ? colorScheme.error : colorScheme.primary;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      height: 48,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: 0.52)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: selected ? null : () => onChanged(value),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? accent : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? accent : colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencySelector extends StatelessWidget {
  const _CurrencySelector({
    required this.currencies,
    required this.selectedCurrency,
    required this.onChanged,
  });

  final List<String> currencies;
  final String selectedCurrency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (currencies.length == 1) {
      final currency = currencies.first;
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: _CurrencyQuickItem(
          currency: currency,
          selected: currency == selectedCurrency,
          fillWidth: true,
          onTap: () {
            if (currency != selectedCurrency) {
              onChanged(currency);
            }
          },
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: currencies.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final currency = currencies[index];
          return _CurrencyQuickItem(
            currency: currency,
            selected: currency == selectedCurrency,
            fillWidth: false,
            onTap: () {
              if (currency != selectedCurrency) {
                onChanged(currency);
              }
            },
          );
        },
      ),
    );
  }
}

class _CurrencyQuickItem extends StatelessWidget {
  const _CurrencyQuickItem({
    required this.currency,
    required this.selected,
    required this.fillWidth,
    required this.onTap,
  });

  final String currency;
  final bool selected;
  final bool fillWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = currency.trim().toUpperCase();

    return AnimatedContainer(
      width: fillWidth ? double.infinity : null,
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.58)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.52)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: fillWidth
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  label == 'CNY'
                      ? Icons.currency_yuan_rounded
                      : Icons.currency_exchange_rounded,
                  size: 18,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    Text(
                      label == 'CNY' ? '人民币' : '账本币种',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.selectedCategory,
    required this.isIncome,
    required this.onChanged,
  });

  final List<String> categories;
  final String selectedCategory;
  final bool isIncome;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          return _CategoryQuickItem(
            category: category,
            icon: _iconFor(category),
            selected: category == selectedCategory,
            isIncome: isIncome,
            onTap: () {
              if (category != selectedCategory) {
                onChanged(category);
              }
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(String category) {
    return switch (category) {
      '交通' => Icons.directions_bus_filled_outlined,
      '购物' => Icons.shopping_bag_outlined,
      '餐饮' => Icons.restaurant_outlined,
      '杂费' => Icons.widgets_outlined,
      '娱乐' => Icons.sports_esports_outlined,
      '居住' => Icons.home_outlined,
      '工资' => Icons.badge_outlined,
      '兼职' => Icons.work_outline_rounded,
      '理财' => Icons.account_balance_outlined,
      '红包' => Icons.card_giftcard_rounded,
      '其他' => Icons.more_horiz_rounded,
      _ => Icons.category_outlined,
    };
  }
}

class _CategoryQuickItem extends StatelessWidget {
  const _CategoryQuickItem({
    required this.category,
    required this.icon,
    required this.selected,
    required this.isIncome,
    required this.onTap,
  });

  final String category;
  final IconData icon;
  final bool selected;
  final bool isIncome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isIncome ? colorScheme.primary : colorScheme.error;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: 0.52)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? accent : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? accent : colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.first,
    required this.second,
    this.breakpoint = 420,
  });

  final Widget first;
  final Widget second;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), second],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
