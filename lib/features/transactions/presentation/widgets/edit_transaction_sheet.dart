import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person_lookup.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../providers/transaction_provider.dart';
import 'transaction_form_components.dart';

class EditTransactionSheet extends ConsumerStatefulWidget {
  const EditTransactionSheet({
    super.key,
    required this.transaction,
    required this.ledger,
  });

  final TransactionRecord transaction;
  final Ledger ledger;

  @override
  ConsumerState<EditTransactionSheet> createState() =>
      _EditTransactionSheetState();
}

class _EditTransactionSheetState extends ConsumerState<EditTransactionSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late int _transactionType;
  late String _selectedCategory;
  late String _selectedCurrency;
  String? _payerPersonUuid;
  final Set<String> _selectedPersonIds = {};
  bool _saving = false;

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
    _amountController = TextEditingController(
      text: _editableAmount(widget.transaction.amount),
    );
    _noteController = TextEditingController(text: widget.transaction.note);
    _transactionType = widget.transaction.type == 1 ? 1 : 0;
    _selectedCurrency = widget.transaction.currencyCode.trim().toUpperCase();
    _payerPersonUuid = widget.transaction.payerPersonUuid;
    _selectedCategory = _categoryOrDefault(widget.transaction.category);
    _selectedPersonIds.addAll(widget.transaction.personUuids);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
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

  void _setTransactionType(int type) {
    if (_transactionType == type) return;
    setState(() {
      _transactionType = type;
      if (_transactionType == 1) {
        _payerPersonUuid = null;
      }
      _selectedCategory = _currentCategories.first;
    });
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

  Future<void> _saveChanges() async {
    if (_saving) return;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      AppNotice.error(context, '请输入大于 0 的有效金额');
      return;
    }

    if (_selectedPersonIds.isEmpty) {
      AppNotice.error(context, '请至少选择一个参与人员');
      return;
    }

    final oldAmount = widget.transaction.amount;
    final oldCurrencyCode = widget.transaction.currencyCode;
    final oldType = widget.transaction.type;
    final oldPayerPersonUuid = widget.transaction.payerPersonUuid;
    final oldCategory = widget.transaction.category;
    final oldNote = widget.transaction.note;
    final oldPersonUuids = List<String>.from(widget.transaction.personUuids);

    widget.transaction.amount = amount;
    widget.transaction.currencyCode = _selectedCurrency;
    widget.transaction.type = _transactionType;
    widget.transaction.payerPersonUuid = _transactionType == 0
        ? _payerPersonUuid
        : null;
    widget.transaction.category = _selectedCategory;
    widget.transaction.note = _noteController.text.trim();
    widget.transaction.personUuids = _selectedPersonIds.toList();

    setState(() => _saving = true);
    try {
      await ref
          .read(transactionNotifierProvider(widget.ledger.uuid).notifier)
          .updateTransaction(widget.transaction);
    } catch (e) {
      widget.transaction.amount = oldAmount;
      widget.transaction.currencyCode = oldCurrencyCode;
      widget.transaction.type = oldType;
      widget.transaction.payerPersonUuid = oldPayerPersonUuid;
      widget.transaction.category = oldCategory;
      widget.transaction.note = oldNote;
      widget.transaction.personUuids = oldPersonUuids;
      if (!mounted) return;
      AppNotice.error(
        context,
        FriendlyError.message(e, fallback: '保存失败，请稍后重试。'),
      );
      setState(() => _saving = false);
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = _stableSheetHeight(
      viewportHeight: viewportHeight,
      bottomInset: bottomInset,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final currencyOptions = supportedCurrenciesForLedger(widget.ledger);
    if (!currencyOptions.contains(_selectedCurrency)) {
      _selectedCurrency = currencyOptions.last;
    }
    final peopleAsyncValue = ref.watch(
      personNotifierProvider(
        includeDeleted: true,
        ledgerUuid: widget.ledger.uuid,
      ),
    );

    return AnimatedPadding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: bottomInset + 16,
      ),
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EditSheetHeader(
                ledger: widget.ledger,
                transactionType: _transactionType,
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppAnimatedEntry(
                        child: AppSectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TransactionTypeSelector(
                                selectedType: _transactionType,
                                onChanged: _setTransactionType,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                    decoration: InputDecoration(
                                      labelText: '金额',
                                      hintText: '0.00',
                                      hintStyle: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.62),
                                            fontWeight: FontWeight.w700,
                                          ),
                                      prefixText: '$_selectedCurrency ',
                                      prefixStyle: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    onChanged: _limitAmountPrecision,
                                  ),
                                ),
                                second: CurrencySelector(
                                  currencies: currencyOptions,
                                  selectedCurrency: _selectedCurrency,
                                  onChanged: (currency) {
                                    setState(() {
                                      _selectedCurrency = currency;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppAnimatedEntry(
                        delay: const Duration(milliseconds: 60),
                        child: AppSectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppAnimatedSwitcher(
                                child: AppSectionHeader(
                                  key: ValueKey(
                                    'edit-category-header-$_transactionType',
                                  ),
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
                                selectedCategory: _selectedCategory,
                                isIncome: _transactionType == 1,
                                onChanged: (category) {
                                  setState(() {
                                    _selectedCategory = category;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppAnimatedEntry(
                        delay: const Duration(milliseconds: 120),
                        child: peopleAsyncValue.when(
                          loading: () => const AppSectionCard(
                            child: Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                          error: (err, st) => AppSectionCard(
                            child: Text(
                              FriendlyError.message(
                                err,
                                fallback: '人员加载失败，请稍后重试。',
                              ),
                            ),
                          ),
                          data: (peoplePool) {
                            final visiblePersonIds = _visiblePersonIds();
                            if (visiblePersonIds.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final personMap = peopleByUuid(peoplePool);
                            final personChoices = visiblePersonIds.map((pid) {
                              final person = personOrFallback(personMap, pid);
                              return AppPersonChoiceItem(
                                id: pid,
                                name: person.isDeleted
                                    ? '${person.name}（已删除）'
                                    : person.name,
                                avatar: person.avatar,
                              );
                            }).toList();

                            return AppAnimatedSwitcher(
                              child: AppSectionCard(
                                key: ValueKey(
                                  'edit-people-${widget.transaction.uuid}-$_transactionType',
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                                  'edit-payment-mode-panel',
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
                                                    setState(() {
                                                      if (paidByPerson) {
                                                        _payerPersonUuid ??=
                                                            _selectedPersonIds
                                                                .isNotEmpty
                                                            ? _selectedPersonIds
                                                                  .first
                                                            : visiblePersonIds
                                                                  .first;
                                                      } else {
                                                        _payerPersonUuid = null;
                                                      }
                                                    });
                                                  },
                                                ),
                                              )
                                            : const SizedBox.shrink(
                                                key: ValueKey(
                                                  'edit-payment-mode-empty',
                                                ),
                                              ),
                                      ),
                                    ),
                                    AppSectionHeader(
                                      title: _transactionType == 0
                                          ? '使用人员'
                                          : '参与人员',
                                      trailing: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            if (_selectedPersonIds.length ==
                                                visiblePersonIds.length) {
                                              _selectedPersonIds.clear();
                                            } else {
                                              _selectedPersonIds
                                                ..clear()
                                                ..addAll(visiblePersonIds);
                                            }
                                          });
                                        },
                                        child: Text(
                                          _selectedPersonIds.length ==
                                                  visiblePersonIds.length
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
                                        setState(() {
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
                                                  'edit-payer-person-panel',
                                                ),
                                                padding: const EdgeInsets.only(
                                                  top: 16,
                                                ),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: colorScheme
                                                        .surfaceContainerLow,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    border: Border.all(
                                                      color: colorScheme
                                                          .outlineVariant
                                                          .withValues(
                                                            alpha: 0.72,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Text(
                                                          '付款人',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall,
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        AppPersonChoiceGrid(
                                                          items: personChoices,
                                                          selectedId:
                                                              _payerPersonUuid,
                                                          onSelect: (pid) {
                                                            setState(() {
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
                                                key: ValueKey(
                                                  'edit-payer-person-empty',
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
                      const SizedBox(height: 14),
                      AppAnimatedEntry(
                        delay: const Duration(milliseconds: 180),
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
                      const SizedBox(height: 18),
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
                  minimum: const EdgeInsets.only(top: 12),
                  child: TransactionSaveButton(
                    onPressed: _saving ? null : _saveChanges,
                    loading: _saving,
                    readyLabel: '保存修改',
                    loadingLabel: '保存中',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _visiblePersonIds() {
    return {
      ...widget.ledger.personUuids,
      ...widget.transaction.personUuids,
      if (widget.transaction.payerPersonUuid != null)
        widget.transaction.payerPersonUuid!,
    }.toList();
  }

  String _editableAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  double _stableSheetHeight({
    required double viewportHeight,
    required double bottomInset,
  }) {
    final maxHeight = viewportHeight * 0.9;
    final availableHeight = (viewportHeight - bottomInset - 24).clamp(
      280.0,
      viewportHeight,
    );
    if (availableHeight <= 520) {
      return availableHeight.toDouble();
    }
    return availableHeight.clamp(420.0, maxHeight).toDouble();
  }
}

class _EditSheetHeader extends StatelessWidget {
  const _EditSheetHeader({required this.ledger, required this.transactionType});

  final Ledger ledger;
  final int transactionType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIncome = transactionType == 1;
    final accent = isIncome ? colorScheme.primary : colorScheme.error;

    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Icon(
            isIncome ? Icons.savings_outlined : Icons.receipt_long_outlined,
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '编辑明细',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '${ledger.name} · ${ledger.displayCode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}
