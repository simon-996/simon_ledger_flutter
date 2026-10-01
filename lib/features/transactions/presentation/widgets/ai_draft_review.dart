import 'package:flutter/material.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/preferences/transaction_category_preference.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../../core/theme/app_theme.dart';
import 'transaction_form_components.dart';

class AiDraftReview extends StatefulWidget {
  const AiDraftReview({
    super.key,
    required this.draft,
    required this.ledger,
    required this.people,
    required this.position,
    required this.total,
    required this.onConfirm,
    required this.onSkip,
    required this.busy,
    this.amountInput,
    this.onChanged,
  });

  final AiDraft draft;
  final Ledger ledger;
  final List<Person> people;
  final int position;
  final int total;
  final String? amountInput;
  final Future<void> Function(AiDraft draft) onConfirm;
  final VoidCallback onSkip;
  final bool busy;
  final void Function(AiDraft draft, String amountInput)? onChanged;

  @override
  State<AiDraftReview> createState() => _AiDraftReviewState();
}

class _AiDraftReviewState extends State<AiDraftReview> {
  static const _paymentDecision = '请确认付款方式';
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final Set<String> _people;
  late final List<String> _unresolved;
  late int _type;
  late String _currency;
  String? _category;
  DateTime? _date;
  String? _payer;
  bool _validationActive = false;
  final _amountFocus = FocusNode();
  final _amountAnchor = GlobalKey();
  final _categoryAnchor = GlobalKey();
  final _peopleAnchor = GlobalKey();
  final _unknownAnchor = GlobalKey();
  final _dateAnchor = GlobalKey();
  String? get _amountError {
    final value = double.tryParse(_amount.text.trim());
    return _validationActive && (value == null || !value.isFinite || value <= 0)
        ? '请输入大于 0 的有效金额'
        : null;
  }

  String? get _categoryError =>
      _validationActive &&
          (_category == null || !_categories.contains(_category))
      ? '请选择分类'
      : null;
  String? get _peopleError =>
      _validationActive && _people.isEmpty ? '请至少选择一个参与人员' : null;
  String? get _unknownError =>
      _validationActive && _unresolved.isNotEmpty ? '请确认待识别姓名和付款方式' : null;
  String? get _dateError =>
      _validationActive &&
          _date != null &&
          DateUtils.dateOnly(
            _date!.toLocal(),
          ).isAfter(DateUtils.dateOnly(DateTime.now()))
      ? '日期不能晚于今天'
      : null;

  List<String> _expenseCategories =
      TransactionCategoryPreference.defaultExpenseCategories;
  List<String> _incomeCategories =
      TransactionCategoryPreference.defaultIncomeCategories;

  List<String> get _categories =>
      _type == 1 ? _incomeCategories : _expenseCategories;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _amount = TextEditingController(
      text: widget.amountInput ?? draft.amount.toStringAsFixed(2),
    );
    _note = TextEditingController(text: draft.note ?? '');
    _type = draft.type;
    _currency = draft.currencyCode;
    _date = draft.happenedAt;
    final validPeople = widget.people.map((person) => person.uuid).toSet();
    _people = draft.personUuids.where(validPeople.contains).toSet();
    _payer = validPeople.contains(draft.payerPersonUuid)
        ? draft.payerPersonUuid
        : null;
    final stalePeople = draft.personUuids
        .where((id) => !validPeople.contains(id))
        .toList();
    _unresolved = {
      ...draft.unresolvedNames,
      for (var index = 0; index < stalePeople.length; index++)
        '原参与人已失效 ${index + 1}',
      if (draft.payerPersonUuid != null && _payer == null) '原付款人已失效',
      if (draft.type == 0 &&
          _payer == null &&
          (draft.unresolvedNames.isNotEmpty || draft.payerPersonUuid != null))
        _paymentDecision,
    }.toList();
    _category = _categories.contains(draft.categorySuggestion)
        ? draft.categorySuggestion
        : null;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await TransactionCategoryPreference.read();
    if (!mounted) return;
    setState(() {
      _expenseCategories = categories.expense;
      _incomeCategories = categories.income;
      if (_categories.contains(widget.draft.categorySuggestion)) {
        _category ??= widget.draft.categorySuggestion;
      }
    });
  }

  @override
  void dispose() {
    _amountFocus.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  AiDraft _editedDraft() => AiDraft(
    sourceText: widget.draft.sourceText,
    type: _type,
    amount: double.tryParse(_amount.text.trim()) ?? widget.draft.amount,
    currencyCode: _currency,
    categorySuggestion: _category ?? widget.draft.categorySuggestion,
    note: _note.text.trim(),
    happenedAt: _date,
    payerPersonUuid: _type == 0 ? _payer : null,
    personUuids: _people.toList(),
    unresolvedNames: [..._unresolved],
  );

  void _changed() {
    setState(() {});
    widget.onChanged?.call(_editedDraft(), _amount.text);
  }

  Future<void> _addCategory() async {
    final type = _type;
    final value = await showTransactionCategoryCreateSheet(
      context: context,
      categories: _categories,
      isIncome: type == 1,
    );
    if (value == null) return;
    final categories = await TransactionCategoryPreference.addCategory(
      transactionType: type,
      category: value,
    );
    if (!mounted) return;
    setState(() {
      _expenseCategories = categories.expense;
      _incomeCategories = categories.income;
      if (_type == type) _category = value;
    });
    _changed();
  }

  Future<void> _confirm() async {
    setState(() => _validationActive = true);
    final amount = double.tryParse(_amount.text.trim());
    if (_amountError != null) {
      revealTransactionField(_amountAnchor, focus: _amountFocus);
      return;
    }
    if (_categoryError != null) {
      revealTransactionField(_categoryAnchor);
      return;
    }
    if (_peopleError != null) {
      revealTransactionField(_peopleAnchor);
      return;
    }
    if (_unknownError != null) {
      revealTransactionField(_unknownAnchor);
      return;
    }
    if (_dateError != null) {
      revealTransactionField(_dateAnchor);
      return;
    }
    await widget.onConfirm(
      AiDraft(
        sourceText: widget.draft.sourceText,
        type: _type,
        amount: amount!,
        currencyCode: _currency,
        categorySuggestion: _category,
        note: _note.text.trim(),
        happenedAt: _date,
        payerPersonUuid: _type == 0 ? _payer : null,
        personUuids: _people.toList(),
        unresolvedNames: const [],
      ),
    );
  }

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: AppTheme.headingWeight),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final currencies = supportedCurrenciesForLedger(widget.ledger);
    if (!currencies.contains(_currency)) _currency = currencies.first;
    final suggestion = widget.draft.categorySuggestion?.trim();
    final unknownSuggestion =
        suggestion != null &&
        suggestion.isNotEmpty &&
        !_categories.contains(suggestion);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '第 ${widget.position}/${widget.total} 笔',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: AppTheme.emphasisWeight,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: widget.position / widget.total),
              if (widget.draft.sourceText?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '原文：${widget.draft.sourceText}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (widget.draft.sourceText!.length > 60)
                          TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('本笔原文'),
                                content: SingleChildScrollView(
                                  child: Text(widget.draft.sourceText!),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('关闭'),
                                  ),
                                ],
                              ),
                            ),
                            child: const Text('查看完整原文'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section(
                  '金额与类型',
                  Column(
                    children: [
                      TransactionTypeSelector(
                        selectedType: _type,
                        onChanged: (type) {
                          if (widget.busy) return;
                          setState(() {
                            _type = type;
                            if (!_categories.contains(_category)) {
                              _category = null;
                            }
                            if (type == 1) _payer = null;
                            if (type == 1) {
                              _unresolved.remove('原付款人已失效');
                              _unresolved.remove(_paymentDecision);
                            } else if (_payer == null &&
                                _unresolved.isNotEmpty) {
                              _unresolved.add(_paymentDecision);
                            }
                          });
                          _changed();
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: _amountAnchor,
                        focusNode: _amountFocus,
                        controller: _amount,
                        enabled: !widget.busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _changed(),
                        decoration: InputDecoration(
                          labelText: '金额',
                          errorText: _amountError,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CurrencySelector(
                        currencies: currencies,
                        selectedCurrency: _currency,
                        onChanged: (value) {
                          if (widget.busy) return;
                          setState(() => _currency = value);
                          _changed();
                        },
                      ),
                    ],
                  ),
                ),
                _section(
                  '分类与时间',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (unknownSuggestion && _category == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('AI 建议「$suggestion」不在现有分类中，请选择或新建分类。'),
                        ),
                      CategorySelector(
                        key: _categoryAnchor,
                        categories: _categories,
                        selectedCategory: _category ?? '',
                        isIncome: _type == 1,
                        onChanged: (category) {
                          if (widget.busy) return;
                          setState(() => _category = category);
                          _changed();
                        },
                        onAddCategory: widget.busy ? null : _addCategory,
                      ),
                      TransactionFieldError(message: _categoryError),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _category == null ? '尚未选择分类' : '已选分类：$_category',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TransactionDateControl(
                        key: _dateAnchor,
                        date: _date,
                        enabled: !widget.busy,
                        onChanged: (date) {
                          setState(() => _date = date);
                          _changed();
                        },
                      ),
                      TransactionFieldError(message: _dateError),
                    ],
                  ),
                ),
                _section(
                  _type == 0 ? '谁承担与谁付款' : '谁收款',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_unresolved.isNotEmpty) ...[
                        Text('请确认未识别的人员，以及这笔支出的付款方式。', key: _unknownAnchor),
                        const SizedBox(height: 8),
                        for (final name in [..._unresolved])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    decoration: InputDecoration(
                                      labelText: name == _paymentDecision
                                          ? '选择付款人'
                                          : '「$name」对应人员',
                                    ),
                                    items: widget.people
                                        .map(
                                          (person) => DropdownMenuItem(
                                            value: person.uuid,
                                            child: Text(person.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: widget.busy
                                        ? null
                                        : (value) {
                                            if (value == null) return;
                                            setState(() {
                                              if (name == '原付款人已失效' ||
                                                  name == _paymentDecision) {
                                                _payer = value;
                                                _unresolved.remove(
                                                  _paymentDecision,
                                                );
                                              } else {
                                                _people.add(value);
                                              }
                                              _unresolved.remove(name);
                                            });
                                            _changed();
                                          },
                                  ),
                                ),
                                TextButton(
                                  onPressed: widget.busy
                                      ? null
                                      : () {
                                          setState(() {
                                            if (name == _paymentDecision) {
                                              _payer = null;
                                            }
                                            _unresolved.remove(name);
                                          });
                                          _changed();
                                        },
                                  child: Text(
                                    name == _paymentDecision
                                        ? '使用共同钱包'
                                        : '忽略$name',
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      TransactionFieldError(message: _unknownError),
                      AppPersonChoiceGrid(
                        key: _peopleAnchor,
                        items: widget.people
                            .map(
                              (person) => AppPersonChoiceItem(
                                id: person.uuid,
                                name: person.name,
                                avatar: person.avatar,
                              ),
                            )
                            .toList(),
                        selectedIds: _people,
                        onToggle: (id, selected) {
                          if (widget.busy) return;
                          setState(() {
                            if (selected) {
                              _people.add(id);
                            } else {
                              _people.remove(id);
                            }
                          });
                          _changed();
                        },
                      ),
                      TransactionFieldError(message: _peopleError),
                      if (_type == 0) ...[
                        const SizedBox(height: 12),
                        PaymentModePanel(
                          paidByPerson: _payer != null,
                          description: _payer == null
                              ? '谁付款 · 共同钱包'
                              : '谁付款 · 选择垫付人',
                          onChanged: (paidByPerson) {
                            if (widget.busy) return;
                            setState(() {
                              _payer = paidByPerson
                                  ? (_people.firstOrNull ??
                                        widget.people.firstOrNull?.uuid)
                                  : null;
                              _unresolved.remove(_paymentDecision);
                              _unresolved.remove('原付款人已失效');
                            });
                            _changed();
                          },
                        ),
                        if (_payer != null) ...[
                          const SizedBox(height: 8),
                          const Text('谁付款'),
                          AppPersonChoiceGrid(
                            items: widget.people
                                .map(
                                  (person) => AppPersonChoiceItem(
                                    id: person.uuid,
                                    name: person.name,
                                    avatar: person.avatar,
                                  ),
                                )
                                .toList(),
                            selectedId: _payer,
                            onSelect: (id) {
                              if (widget.busy) return;
                              setState(() => _payer = id);
                              _changed();
                            },
                          ),
                        ],
                      ],
                      TransactionSplitSummary(
                        ledger: widget.ledger,
                        type: _type,
                        amount: double.tryParse(_amount.text),
                        currency: _currency,
                        participantCount: _people.length,
                        payerName: _payer == null
                            ? null
                            : widget.people
                                  .where((person) => person.uuid == _payer)
                                  .firstOrNull
                                  ?.name,
                      ),
                    ],
                  ),
                ),
                _section(
                  '备注',
                  TextField(
                    controller: _note,
                    enabled: !widget.busy,
                    maxLines: 2,
                    onChanged: (_) => _changed(),
                    decoration: const InputDecoration(labelText: '备注（选填）'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Row(
            children: [
              TextButton(
                onPressed: widget.busy ? null : widget.onSkip,
                child: const Text('跳过此笔'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: widget.busy ? null : _confirm,
                  child: const Text('确认记账'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
