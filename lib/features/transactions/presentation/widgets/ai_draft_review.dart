import 'package:flutter/material.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';

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
  });

  final AiDraft draft;
  final Ledger ledger;
  final List<Person> people;
  final int position;
  final int total;
  final Future<void> Function(AiDraft draft) onConfirm;
  final VoidCallback onSkip;
  final bool busy;

  @override
  State<AiDraftReview> createState() => _AiDraftReviewState();
}

class _AiDraftReviewState extends State<AiDraftReview> {
  late final TextEditingController _amount;
  late final TextEditingController _category;
  late final TextEditingController _note;
  late final TextEditingController _date;
  late final Set<String> _people;
  late int _type;
  late String _currency;
  String? _payer;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _amount = TextEditingController(text: draft.amount.toStringAsFixed(2));
    _category = TextEditingController(text: draft.categorySuggestion ?? '');
    _note = TextEditingController(text: draft.note ?? '');
    _date = TextEditingController(text: draft.happenedAt?.toIso8601String() ?? '');
    _type = draft.type;
    _currency = draft.currencyCode;
    final validPeople = widget.people.map((person) => person.uuid).toSet();
    _people = draft.personUuids.where(validPeople.contains).toSet();
    _payer = validPeople.contains(draft.payerPersonUuid)
        ? draft.payerPersonUuid : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amount.text.trim());
    final category = _category.text.trim();
    final date = _date.text.trim().isEmpty ? null : DateTime.tryParse(_date.text.trim());
    final currencies = supportedCurrenciesForLedger(widget.ledger);
    if (amount == null || !amount.isFinite || amount <= 0 ||
        category.isEmpty || category.length > 64 || _people.isEmpty ||
        !currencies.contains(_currency) ||
        (_date.text.trim().isNotEmpty && date == null)) {
      setState(() => _error = '请检查金额、分类、币种、时间和参与人员');
      return;
    }
    setState(() => _error = null);
    await widget.onConfirm(AiDraft(
      sourceText: widget.draft.sourceText,
      type: _type,
      amount: amount,
      currencyCode: _currency,
      categorySuggestion: category,
      note: _note.text.trim(),
      happenedAt: date,
      payerPersonUuid: _type == 0 ? _payer : null,
      personUuids: _people.toList(),
      unresolvedNames: widget.draft.unresolvedNames,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final currencies = supportedCurrenciesForLedger(widget.ledger);
    if (!currencies.contains(_currency)) _currency = currencies.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('第 ${widget.position}/${widget.total} 笔',
        style: Theme.of(context).textTheme.titleMedium),
      if (widget.draft.sourceText?.isNotEmpty == true)
        Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('原文：${widget.draft.sourceText}')),
      if (widget.draft.unresolvedNames.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('待确认参与人：${widget.draft.unresolvedNames.join('、')}')),
      const SizedBox(height: 12),
      SegmentedButton<int>(segments: const [
        ButtonSegment(value: 0, label: Text('支出')),
        ButtonSegment(value: 1, label: Text('收入')),
      ], selected: {_type}, onSelectionChanged: widget.busy ? null : (value) =>
        setState(() => _type = value.first)),
      const SizedBox(height: 12),
      TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '金额')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: _currency,
        decoration: const InputDecoration(labelText: '币种'),
        items: currencies.map((currency) => DropdownMenuItem(value: currency,
          child: Text(currency))).toList(),
        onChanged: widget.busy ? null : (value) => setState(() => _currency = value!)),
      const SizedBox(height: 12),
      TextField(controller: _category, decoration: const InputDecoration(labelText: '分类')),
      const SizedBox(height: 12),
      TextField(controller: _note, decoration: const InputDecoration(labelText: '备注')),
      const SizedBox(height: 12),
      TextField(controller: _date, decoration: const InputDecoration(
        labelText: '发生时间（选填）', hintText: '2026-09-30T12:00:00')),
      const SizedBox(height: 12),
      Text('参与人员', style: Theme.of(context).textTheme.titleSmall),
      for (final person in widget.people)
        CheckboxListTile(
          value: _people.contains(person.uuid),
          title: Text(person.name),
          onChanged: widget.busy ? null : (value) => setState(() {
            if (value == true) { _people.add(person.uuid); }
            else { _people.remove(person.uuid); }
          }),
        ),
      if (_type == 0)
        DropdownButtonFormField<String?>(
          initialValue: _payer,
          decoration: const InputDecoration(labelText: '付款人（选填）'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('公共资金')),
            ...widget.people.map((person) => DropdownMenuItem<String?>(
              value: person.uuid, child: Text(person.name))),
          ],
          onChanged: widget.busy ? null : (value) => setState(() => _payer = value),
        ),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 16),
      FilledButton(onPressed: widget.busy ? null : _confirm, child: const Text('确认记账')),
      TextButton(onPressed: widget.busy ? null : widget.onSkip, child: const Text('跳过此笔')),
    ]);
  }
}
