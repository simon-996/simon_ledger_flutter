import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/di/providers.dart';
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
      _selectedCurrency = currentLedger.baseCurrencyCode;
      if (!currentLedger.personUuids.contains(_payerPersonUuid)) {
        _payerPersonUuid = null;
      }
      _selectedPersonIds.retainWhere(currentLedger.personUuids.contains);
      if (_selectedPersonIds.isEmpty && currentLedger.personUuids.isNotEmpty) {
        _selectedPersonIds.add(currentLedger.personUuids.first);
      }
    });
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
    _selectedCategory ??= _currentCategories.first;

    final lastUuid = await LastSelectedLedgerPreference.getUuid();

    if (!mounted || widget.ledgers.isEmpty) return;

    setState(() {
      if (lastUuid != null && widget.ledgers.any((l) => l.uuid == lastUuid)) {
        _updateSelectedLedger(lastUuid);
      } else if (widget.ledgers.length == 1) {
        _updateSelectedLedger(widget.ledgers.first.uuid);
      } else {
        _selectedLedgerUuid = null;
      }
    });
  }

  void _updateSelectedLedger(String ledgerUuid) {
    _selectedLedgerUuid = ledgerUuid;
    final ledger = widget.ledgers.firstWhere((l) => l.uuid == ledgerUuid);
    _selectedCurrency = ledger.baseCurrencyCode;
    if (!ledger.personUuids.contains(_payerPersonUuid)) {
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

    LastSelectedLedgerPreference.setUuid(ledgerUuid);
  }

  List<String> get _currentCategories {
    return _transactionType == 0 ? _expenseCategories : _incomeCategories;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败，请重试：$e')));
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
                    ledger: selectedLedger,
                    currencyCode: _selectedCurrency,
                    isIncome: _transactionType == 1,
                  ),
                ),
                const SizedBox(height: 14),
                AppAnimatedEntry(
                  delay: const Duration(milliseconds: 60),
                  child: AppSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ResponsivePair(
                          breakpoint: 430,
                          first: DropdownButtonFormField<String>(
                            key: ValueKey('ledger-$_selectedLedgerUuid'),
                            initialValue: _selectedLedgerUuid,
                            decoration: const InputDecoration(
                              labelText: '所属账本',
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
                              if (val == null) return;
                              setState(() => _updateSelectedLedger(val));
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
                              setState(() {
                                _transactionType = newSelection.first;
                                if (_transactionType == 1) {
                                  _payerPersonUuid = null;
                                }
                                _selectedCategory = _currentCategories.first;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ResponsivePair(
                          breakpoint: 390,
                          firstFlex: 3,
                          secondFlex: 6,
                          first: DropdownButtonFormField<String>(
                            key: ValueKey('currency-$_selectedCurrency'),
                            initialValue: _selectedCurrency,
                            decoration: const InputDecoration(
                              labelText: '币种',
                              prefixIcon: Icon(Icons.payments_outlined),
                            ),
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: 'CNY',
                                child: Text('CNY'),
                              ),
                              DropdownMenuItem(
                                value: 'USD',
                                child: Text('USD'),
                              ),
                              DropdownMenuItem(
                                value: 'EUR',
                                child: Text('EUR'),
                              ),
                              DropdownMenuItem(
                                value: 'JPY',
                                child: Text('JPY'),
                              ),
                              DropdownMenuItem(
                                value: 'THB',
                                child: Text('THB'),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _selectedCurrency = val),
                          ),
                          second: TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _currentCategories.map((cat) {
                            final isSelected = _selectedCategory == cat;
                            return ChoiceChip(
                              label: Text(cat),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedCategory = cat);
                                }
                              },
                            );
                          }).toList(),
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
                      error: (e, st) =>
                          AppSectionCard(child: Text('加载人员失败: $e')),
                      data: (peoplePool) {
                        if (selectedLedger.personUuids.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        final personMap = peopleByUuid(peoplePool);
                        return AppAnimatedSwitcher(
                          child: AppSectionCard(
                            key: ValueKey(
                              'people-${selectedLedger.uuid}-$_transactionType-${_payerPersonUuid != null}',
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AppSectionHeader(
                                  title: _transactionType == 0
                                      ? '使用人员'
                                      : '参与人员',
                                  trailing: TextButton(
                                    onPressed: () {
                                      setState(() {
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
                                      setState(() {
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
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: selectedLedger.personUuids.map((
                                    pid,
                                  ) {
                                    final person = personOrFallback(
                                      personMap,
                                      pid,
                                    );
                                    final isSelected = _selectedPersonIds
                                        .contains(pid);
                                    return FilterChip(
                                      avatar: Text(person.avatar),
                                      label: Text(person.name),
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        setState(() {
                                          if (selected) {
                                            _selectedPersonIds.add(pid);
                                          } else {
                                            _selectedPersonIds.remove(pid);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                                if (_transactionType == 0 &&
                                    _payerPersonUuid != null) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    '付款人',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: selectedLedger.personUuids.map((
                                      pid,
                                    ) {
                                      final person = personOrFallback(
                                        personMap,
                                        pid,
                                      );
                                      return ChoiceChip(
                                        avatar: Text(person.avatar),
                                        label: Text(person.name),
                                        selected: _payerPersonUuid == pid,
                                        onSelected: (_) {
                                          setState(() {
                                            _payerPersonUuid = pid;
                                          });
                                        },
                                      );
                                    }).toList(),
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
    required this.ledger,
    required this.currencyCode,
    required this.isIncome,
  });

  final Ledger? ledger;
  final String? currencyCode;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isIncome ? colorScheme.primary : colorScheme.error;

    return AppSectionCard(
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

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.first,
    required this.second,
    this.firstFlex = 1,
    this.secondFlex = 1,
    this.breakpoint = 420,
  });

  final Widget first;
  final Widget second;
  final int firstFlex;
  final int secondFlex;
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
            Expanded(flex: firstFlex, child: first),
            const SizedBox(width: 12),
            Expanded(flex: secondFlex, child: second),
          ],
        );
      },
    );
  }
}
