import 'package:flutter/material.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/preferences/transaction_category_preference.dart';
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
  String? _error;
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
    _error = null;
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

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final initialDate = _date ?? now;
    final day = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(initialDate.year < 2000 ? initialDate.year : 2000),
      lastDate: DateTime(
        initialDate.year > now.year + 10 ? initialDate.year : now.year + 10,
        12,
        31,
      ),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date ?? now),
    );
    if (time == null || !mounted) return;
    setState(
      () => _date = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
    _changed();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        _category == null ||
        !_categories.contains(_category) ||
        _people.isEmpty ||
        _unresolved.isNotEmpty ||
        !supportedCurrenciesForLedger(widget.ledger).contains(_currency)) {
      setState(() => _error = '请先核对金额、分类、币种、参与人和待确认姓名');
      return;
    }
    setState(() => _error = null);
    await widget.onConfirm(
      AiDraft(
        sourceText: widget.draft.sourceText,
        type: _type,
        amount: amount,
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
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
                        controller: _amount,
                        enabled: !widget.busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _changed(),
                        decoration: const InputDecoration(labelText: '金额'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('currency-$_currency'),
                        initialValue: _currency,
                        decoration: const InputDecoration(labelText: '币种'),
                        items: currencies
                            .map(
                              (currency) => DropdownMenuItem(
                                value: currency,
                                child: Text(currency),
                              ),
                            )
                            .toList(),
                        onChanged: widget.busy
                            ? null
                            : (value) {
                                if (value == null) return;
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
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _category == null ? '尚未选择分类' : '已选分类：$_category',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: widget.busy ? null : _chooseDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _date == null
                              ? '选择发生时间 · 留空则记为当前时间'
                              : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}  ${_date!.hour.toString().padLeft(2, '0')}:${_date!.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                      if (_date != null)
                        TextButton(
                          onPressed: widget.busy
                              ? null
                              : () {
                                  setState(() => _date = null);
                                  _changed();
                                },
                          child: const Text('改为当前时间'),
                        ),
                    ],
                  ),
                ),
                _section(
                  '参与人与付款',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_unresolved.isNotEmpty) ...[
                        const Text('请确认未识别的人员，以及这笔支出的付款方式。'),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final person in widget.people)
                            FilterChip(
                              label: Text(person.name),
                              selected: _people.contains(person.uuid),
                              onSelected: widget.busy
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected) {
                                          _people.add(person.uuid);
                                        } else {
                                          _people.remove(person.uuid);
                                        }
                                      });
                                      _changed();
                                    },
                            ),
                        ],
                      ),
                      if (_type == 0) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          key: ValueKey('payer-$_payer'),
                          initialValue: _payer,
                          decoration: const InputDecoration(labelText: '付款人'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('共同钱包'),
                            ),
                            ...widget.people.map(
                              (person) => DropdownMenuItem<String?>(
                                value: person.uuid,
                                child: Text(person.name),
                              ),
                            ),
                          ],
                          onChanged: widget.busy
                              ? null
                              : (value) {
                                  setState(() {
                                    _payer = value;
                                    _unresolved.remove(_paymentDecision);
                                  });
                                  _changed();
                                },
                        ),
                      ],
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
