import 'package:flutter/material.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/preferences/transaction_category_preference.dart';
import '../../../../core/services/ai_draft_readiness.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../../core/theme/app_theme.dart';
import 'transaction_form_components.dart';
import 'ai_person_resolution.dart';
import '../../../../core/services/ai_draft_identity_mapper.dart';

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
    this.initialField,
    this.onBackToSummary,
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
  final String? initialField;
  final VoidCallback? onBackToSummary;

  @override
  State<AiDraftReview> createState() => _AiDraftReviewState();
}

class _AiDraftReviewState extends State<AiDraftReview> {
  static const _paymentDecision = '请确认付款方式';
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final Set<String> _people;
  late final List<String> _unresolved;
  late List<AiDraftIssue> _issues;
  late final List<AiPersonMatch> _personMatches;
  late Map<String, String> _fieldSources;
  late int _type;
  late String _currency;
  late String _paymentMode;
  late String _participantScope;
  late String _splitMode;
  late String _datePrecision;
  String? _category;
  DateTime? _date;
  String? _payer;
  bool _validationActive = false;
  bool _showAllFields = false;
  bool _initialFieldRevealed = false;
  final _amountFocus = FocusNode();
  final _amountAnchor = GlobalKey();
  final _typeAnchor = GlobalKey();
  final _categoryAnchor = GlobalKey();
  final _peopleAnchor = GlobalKey();
  final _unknownAnchor = GlobalKey();
  final _paymentAnchor = GlobalKey();
  final _dateAnchor = GlobalKey();
  final _noteAnchor = GlobalKey();
  String? get _amountError {
    return _validationActive
        ? aiDraftAmountError(widget.draft.amount, amountInput: _amount.text)
        : null;
  }

  String? get _typeError =>
      _validationActive && _type != 0 && _type != 1 ? '请选择收入或支出' : null;
  String? get _currencyError =>
      _validationActive &&
          !supportedCurrenciesForLedger(widget.ledger).contains(_currency)
      ? '草稿币种不受当前账本支持，请明确选择账本币种；金额数值不会自动换算'
      : null;

  String? get _categoryError =>
      _validationActive &&
          (_category == null || !_categories.contains(_category))
      ? '请选择分类'
      : null;
  String? get _peopleError =>
      _validationActive && _people.isEmpty ? '请至少选择一个参与人员' : null;
  String? get _unknownError =>
      _validationActive &&
          (_unresolved.isNotEmpty || _pendingMatches.isNotEmpty)
      ? '请确认待识别人员'
      : null;

  Iterable<AiPersonMatch> get _pendingMatches {
    final validIds = widget.people
        .where((person) => !person.isDeleted)
        .map((person) => person.uuid)
        .toSet();
    return _personMatches.where(
      (match) =>
          !validIds.contains(match.personUuid) &&
          (match.role == 'participant' ||
              (_type == 0 &&
                  match.role == 'payer' &&
                  _paymentMode != 'SHARED_POOL')),
    );
  }

  String? get _paymentError =>
      _validationActive &&
          _type == 0 &&
          (_paymentMode == 'UNKNOWN' ||
              (_paymentMode == 'PERSON_PAID' && _payer == null))
      ? '请明确选择个人垫付或共同钱包，并确认付款人'
      : null;
  String? get _dateError =>
      _validationActive &&
          ((_date == null && widget.draft.schemaVersion >= 2) ||
              (_date != null &&
                  DateUtils.dateOnly(
                    _date!.toLocal(),
                  ).isAfter(DateUtils.dateOnly(DateTime.now()))))
      ? (_date == null ? '请选择日期' : '日期不能晚于今天')
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
    final draft = normalizeAiDraftPeople(widget.draft, widget.people);
    _amount = TextEditingController(
      text:
          widget.amountInput ??
          (aiDraftAmountError(draft.amount) == null
              ? draft.amount.toStringAsFixed(2)
              : draft.amount.toString()),
    );
    _note = TextEditingController(text: draft.note ?? '');
    _type = draft.type;
    _currency = draft.currencyCode;
    _paymentMode = draft.paymentMode;
    _participantScope = draft.participantScope;
    _splitMode = draft.splitMode;
    _datePrecision = draft.datePrecision;
    _issues = List.of(draft.issues);
    _fieldSources = Map.of(draft.fieldSources);
    _date = draft.happenedAt;
    final validPeople = widget.people
        .where((person) => !person.isDeleted)
        .map((person) => person.uuid)
        .toSet();
    _people = draft.personUuids.where(validPeople.contains).toSet();
    _payer = validPeople.contains(draft.payerPersonUuid)
        ? draft.payerPersonUuid
        : null;
    _paymentMode = draft.paymentMode;
    if (_paymentMode == 'SHARED_POOL') _payer = null;
    if (_paymentMode == 'PERSON_PAID' && _payer == null) {
      _paymentMode = 'UNKNOWN';
    }
    _personMatches = draft.personMatches
        .map(
          (match) => AiPersonMatch(
            sourceName: match.sourceName,
            role: match.role,
            personUuid: match.personUuid,
            matchedName: match.matchedName,
            approximate: match.approximate,
            candidatePersonUuids: match.candidatePersonUuids
                .where(validPeople.contains)
                .toList(),
          ),
        )
        .toList();
    final stalePeople = draft.personUuids
        .where((id) => !validPeople.contains(id))
        .toList();
    _unresolved = draft.unresolvedNames
        .where(
          (name) => !_personMatches.any((match) => match.sourceName == name),
        )
        .toSet()
        .toList();
    for (final id in stalePeople) {
      if (!draft.personMatches.any(
        (match) => match.role == 'participant' && match.personUuid == id,
      )) {
        _personMatches.add(
          AiPersonMatch(
            sourceName: '原承担人',
            role: 'participant',
            personUuid: id,
          ),
        );
      }
    }
    if (draft.payerPersonUuid != null &&
        _payer == null &&
        _paymentMode != 'SHARED_POOL' &&
        !_personMatches.any((match) => match.role == 'payer')) {
      _personMatches.add(
        AiPersonMatch(
          sourceName: '原付款人',
          role: 'payer',
          personUuid: draft.payerPersonUuid,
        ),
      );
    }
    _category = _categories.contains(draft.categorySuggestion)
        ? draft.categorySuggestion
        : null;
    _loadCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealInitialField());
  }

  String? get _initialSection => switch (widget.initialField) {
    'amount' || 'type' || 'currencyCode' => 'amount',
    'category' || 'happenedAt' => 'category',
    'payer' ||
    'paymentMode' ||
    'participants' ||
    'excludedParticipants' ||
    'legacy' ||
    'splitMode' => 'people',
    'note' => 'note',
    _ => null,
  };

  bool _showSection(String section) =>
      _showAllFields || _initialSection == null || _initialSection == section;

  void _revealInitialField() {
    if (_initialFieldRevealed || !mounted || widget.initialField == null) {
      return;
    }
    _initialFieldRevealed = true;
    final anchor = switch (widget.initialField) {
      'amount' || 'currencyCode' => _amountAnchor,
      'type' => _typeAnchor,
      'category' => _categoryAnchor,
      'happenedAt' => _dateAnchor,
      'payer' || 'paymentMode' => _paymentAnchor,
      'participants' ||
      'excludedParticipants' ||
      'legacy' ||
      'splitMode' => _peopleAnchor,
      'note' => _noteAnchor,
      _ => null,
    };
    if (anchor != null) {
      revealTransactionField(
        anchor,
        focus: widget.initialField == 'amount' ? _amountFocus : null,
      );
    }
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

  AiDraft _editedDraft() => widget.draft.copyWith(
    type: _type,
    amount: double.tryParse(_amount.text.trim()) ?? widget.draft.amount,
    currencyCode: _currency,
    categorySuggestion: _category,
    note: _note.text.trim(),
    happenedAt: _date,
    payerPersonUuid: _type == 0 ? _payer : null,
    personUuids: _people.toList(),
    unresolvedNames: [..._unresolved],
    paymentMode: _type == 0 ? _paymentMode : 'UNKNOWN',
    participantScope: _participantScope,
    splitMode: _splitMode,
    datePrecision: _datePrecision,
    fieldSources: _fieldSources,
    issues: _issues,
    personMatches: [..._personMatches],
  );

  List<String> get _blockingFields => aiDraftBlockingFields(
    _editedDraft(),
    activePersonIds: widget.people.map((person) => person.uuid).toSet(),
    categories: _categories,
    supportedCurrencies: supportedCurrenciesForLedger(widget.ledger),
    today: DateTime.now(),
    amountInput: _amount.text,
  );

  void _clearIssues(Iterable<String> fields) {
    final selected = fields.toSet();
    _issues = _issues
        .where((issue) => !selected.contains(issue.field))
        .toList();
  }

  void _selectPaymentMode(String mode) {
    if (widget.busy) return;
    setState(() {
      _paymentMode = mode;
      if (mode == 'SHARED_POOL') {
        _payer = null;
        _personMatches.removeWhere((match) => match.role == 'payer');
      }
      _clearIssues(['paymentMode', if (mode == 'SHARED_POOL') 'payer']);
      _fieldSources['paymentMode'] = 'USER';
      if (mode == 'SHARED_POOL') _fieldSources['payer'] = 'USER';
      _unresolved.remove(_paymentDecision);
      if (mode == 'SHARED_POOL') {
        _unresolved.remove('原付款人已失效');
        _unresolved.remove(_paymentDecision);
      }
    });
    _changed();
  }

  void _selectPayer(String id) {
    setState(() {
      _payer = id;
      _paymentMode = 'PERSON_PAID';
      _unresolved.remove('原付款人已失效');
      _unresolved.remove(_paymentDecision);
      _clearIssues(['payer', 'paymentMode']);
      _fieldSources['payer'] = 'USER';
      _fieldSources['paymentMode'] = 'USER';
    });
    for (var index = 0; index < _personMatches.length; index++) {
      if (_personMatches[index].role == 'payer') _resolveMatch(index, id);
    }
    _changed();
  }

  void _confirmParticipantSnapshot() {
    setState(() {
      _participantScope = 'SPECIFIED';
      _fieldSources['participants'] = 'USER';
      _clearIssues(['participants']);
    });
    _changed();
  }

  void _resolveIssue(AiDraftIssue issue, String selectedPersonId) {
    setState(() {
      if (issue.field == 'payer') {
        _payer = selectedPersonId;
        _paymentMode = 'PERSON_PAID';
        _clearIssues(['payer', 'paymentMode']);
        _fieldSources['payer'] = 'USER';
        _fieldSources['paymentMode'] = 'USER';
      } else if (issue.field == 'excludedParticipants') {
        _people.remove(selectedPersonId);
        _issues.removeWhere((value) => value.id == issue.id);
        _participantScope = 'SPECIFIED';
        _fieldSources['participants'] = 'USER';
        _fieldSources['excludedParticipants'] = 'USER';
      }
    });
    _changed();
  }

  void _cancelExclusion(AiDraftIssue issue) {
    setState(() {
      _issues.removeWhere((value) => value.id == issue.id);
      _participantScope = 'SPECIFIED';
      _fieldSources['participants'] = 'USER';
      _fieldSources['excludedParticipants'] = 'USER';
    });
    _changed();
  }

  String _issueMessage(AiDraftIssue issue) {
    final source = issue.sourceText;
    return switch (issue.code) {
      'PAYMENT_UNSPECIFIED' => '请确认这笔支出由谁付款。',
      'PAYER_UNSPECIFIED' => '请从当前账本人员中选择付款人。',
      'PERSON_AMBIGUOUS' => '「${source ?? '该姓名'}」对应多位人员，请选择正确角色。',
      'PERSON_NOT_FOUND' => '账本中找不到「${source ?? '该姓名'}」，请核对人员名单。',
      'PARTICIPANTS_UNSPECIFIED' => '请明确选择这笔费用的承担人员。',
      'CATEGORY_UNMATCHED' => 'AI 的分类建议「${source ?? '未匹配'}」不在当前分类中。',
      'CURRENCY_UNSUPPORTED' => '这笔流水的币种尚不受当前账本支持。',
      'DATE_AMBIGUOUS' => '原文中的日期或时间不明确，请手动确认。',
      'DATE_INVALID' => '日期晚于账本参考日，请修正日期。',
      'UNSUPPORTED_SPLIT' => '当前暂不支持非均摊分配，请先用手动记账处理。',
      'CONFLICTING_FIELDS' => '原文中的字段信息不一致，请逐项核对。',
      'UNSUPPORTED_ENUM' => '服务返回了暂不支持的字段值，请重新确认。',
      _ => '请核对这笔草稿的${issue.field}。',
    };
  }

  Widget _issueCard(AiDraftIssue issue) {
    final selectableRole =
        issue.field == 'payer' || issue.field == 'excludedParticipants';
    final candidateIds = issue.candidateUuids.toSet();
    final candidates = widget.people
        .where(
          (person) =>
              candidateIds.isEmpty || candidateIds.contains(person.uuid),
        )
        .toList();
    return Card(
      key: ValueKey('ai-issue-${issue.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_issueMessage(issue)),
            if (selectableRole) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('ai-issue-choice-${issue.id}'),
                decoration: InputDecoration(
                  labelText: issue.field == 'payer' ? '选择付款人' : '选择不承担的人员',
                ),
                items: candidates
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
                        if (value != null) _resolveIssue(issue, value);
                      },
              ),
            ],
            if (issue.field == 'excludedParticipants')
              TextButton(
                key: ValueKey('ai-cancel-exclusion-${issue.id}'),
                onPressed: widget.busy ? null : () => _cancelExclusion(issue),
                child: const Text('取消这项排除，保留当前名单'),
              ),
          ],
        ),
      ),
    );
  }

  void _changed() {
    setState(() {});
    widget.onChanged?.call(_editedDraft(), _amount.text);
  }

  void _resolveMatch(int index, String id) {
    final match = _personMatches[index];
    final person = widget.people
        .where((person) => person.uuid == id && !person.isDeleted)
        .firstOrNull;
    if (person == null) return;
    if (match.role == 'payer') {
      _payer = id;
      _paymentMode = 'PERSON_PAID';
      _clearIssues(['payer', 'paymentMode']);
      _fieldSources['payer'] = 'USER';
      _fieldSources['paymentMode'] = 'USER';
    } else {
      _people.add(id);
      _participantScope = 'SPECIFIED';
      _fieldSources['participants'] = 'USER';
    }
    _personMatches[index] = AiPersonMatch(
      sourceName: match.sourceName,
      role: match.role,
      personUuid: id,
      matchedName: person.name,
      candidatePersonUuids: [id],
    );
    _changed();
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
      _fieldSources['category'] = 'USER';
      _clearIssues(['category']);
    });
    _changed();
  }

  Future<void> _confirm() async {
    setState(() => _validationActive = true);
    if (_typeError != null || _blockingFields.contains('type')) {
      revealTransactionField(_typeAnchor);
      return;
    }
    if (_amountError != null) {
      revealTransactionField(_amountAnchor, focus: _amountFocus);
      return;
    }
    if (_currencyError != null || _blockingFields.contains('currencyCode')) {
      revealTransactionField(_amountAnchor);
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
    if (_paymentError != null || _blockingFields.contains('paymentMode')) {
      revealTransactionField(_paymentAnchor);
      return;
    }
    if (_blockingFields.contains('payer')) {
      revealTransactionField(_paymentAnchor);
      return;
    }
    if (_blockingFields.contains('participants') ||
        _blockingFields.contains('excludedParticipants') ||
        _blockingFields.contains('legacy')) {
      revealTransactionField(_peopleAnchor);
      return;
    }
    if (_blockingFields.contains('happenedAt')) {
      revealTransactionField(_dateAnchor);
      return;
    }
    if (_blockingFields.isNotEmpty) return;
    await widget.onConfirm(_editedDraft());
  }

  void _useLedgerCurrency(String currency) {
    setState(() {
      _currency = currency;
      _clearIssues(['currencyCode']);
      _fieldSources['currencyCode'] = 'USER';
    });
    _changed();
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
    final currencyIsSupported = currencies.contains(_currency);
    final currencyNeedsReview = _issues.any(
      (issue) => issue.field == 'currencyCode',
    );
    final selectedCurrency = currencyIsSupported ? _currency : currencies.first;
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '第 ${widget.position}/${widget.total} 笔',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: AppTheme.emphasisWeight,
                      ),
                    ),
                  ),
                  if (widget.onBackToSummary != null)
                    TextButton.icon(
                      onPressed: widget.busy ? null : widget.onBackToSummary,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('返回摘要'),
                    ),
                ],
              ),
              if (widget.initialField != null && !_showAllFields)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.busy
                        ? null
                        : () => setState(() => _showAllFields = true),
                    child: const Text('展开全部字段'),
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
                if (_showSection('amount'))
                  _section(
                    '金额与类型',
                    Column(
                      children: [
                        TransactionTypeSelector(
                          key: _typeAnchor,
                          selectedType: _type,
                          onChanged: (type) {
                            if (widget.busy) return;
                            setState(() {
                              _clearIssues(['type', 'category']);
                              _fieldSources['type'] = 'USER';
                              _type = type;
                              if (!_categories.contains(_category)) {
                                _category = null;
                              }
                              if (type == 1) {
                                _personMatches.removeWhere(
                                  (match) => match.role == 'payer',
                                );
                                _payer = null;
                                _paymentMode = 'UNKNOWN';
                                _clearIssues(['payer', 'paymentMode']);
                                _unresolved.remove('原付款人已失效');
                                _unresolved.remove(_paymentDecision);
                              }
                            });
                            _changed();
                          },
                        ),
                        TransactionFieldError(message: _typeError),
                        const SizedBox(height: 12),
                        TextField(
                          key: _amountAnchor,
                          focusNode: _amountFocus,
                          controller: _amount,
                          enabled: !widget.busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) {
                            _fieldSources['amount'] = 'USER';
                            _clearIssues(['amount']);
                            _changed();
                          },
                          decoration: InputDecoration(
                            labelText: '金额',
                            errorText: _amountError,
                          ),
                        ),
                        const SizedBox(height: 12),
                        CurrencySelector(
                          currencies: currencies,
                          selectedCurrency: selectedCurrency,
                          onChanged: (value) {
                            if (widget.busy) return;
                            _useLedgerCurrency(value);
                          },
                        ),
                        if (!currencyIsSupported) ...[
                          TransactionFieldError(message: _currencyError),
                          OutlinedButton(
                            onPressed: widget.busy
                                ? null
                                : () => _useLedgerCurrency(currencies.first),
                            child: Text('按账本币种 ${currencies.first} 继续（不换算金额）'),
                          ),
                        ] else if (currencyNeedsReview) ...[
                          const Text('原文中的币种信息需要核对；确认后金额数值保持不变。'),
                          OutlinedButton(
                            key: const ValueKey('ai-confirm-currency'),
                            onPressed: widget.busy
                                ? null
                                : () => _useLedgerCurrency(_currency),
                            child: Text('确认币种 $_currency（不换算金额）'),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_showSection('category'))
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
                            setState(() {
                              _category = category;
                              _clearIssues(['category']);
                              _fieldSources['category'] = 'USER';
                            });
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
                          hasTime: _datePrecision == 'TIME',
                          onTimePrecisionChanged: (hasTime) {
                            setState(
                              () => _datePrecision = hasTime ? 'TIME' : 'DAY',
                            );
                          },
                          onChanged: (date) {
                            setState(() {
                              _date = date;
                              _clearIssues(['happenedAt']);
                              _fieldSources['happenedAt'] = 'USER';
                            });
                            _changed();
                          },
                        ),
                        TransactionFieldError(message: _dateError),
                      ],
                    ),
                  ),
                if (_showSection('people'))
                  _section(
                    _type == 0 ? '谁承担与谁付款' : '谁收款',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_issues.isNotEmpty) ...[
                          for (final issue in [..._issues]) _issueCard(issue),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(key: _unknownAnchor),
                        for (final match in _personMatches)
                          if (match.approximate &&
                              match.personUuid != null &&
                              (match.role == 'payer'
                                  ? _payer == match.personUuid
                                  : _people.contains(match.personUuid)))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '“${match.sourceName}”已近似匹配为“${match.matchedName ?? match.sourceName}”，可在下方修改。',
                              ),
                            ),
                        for (
                          var index = 0;
                          index < _personMatches.length;
                          index++
                        )
                          if (_pendingMatches.contains(_personMatches[index]))
                            AiPersonResolution(
                              key: ValueKey(
                                'ai-match-${_personMatches[index].role}-${_personMatches[index].sourceName}-$index',
                              ),
                              match: _personMatches[index],
                              missingIdentity:
                                  _personMatches[index].personUuid != null,
                              people: widget.people,
                              busy: widget.busy,
                              onSelected: (id) => _resolveMatch(index, id),
                              onIgnore: () {
                                _personMatches.removeAt(index);
                                _changed();
                              },
                            ),
                        if (_unresolved.isNotEmpty) ...[
                          const Text('旧草稿没有记录人员身份，请先确认承担人或付款人。'),
                          const SizedBox(height: 8),
                          for (final name in [..._unresolved])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('“$name”在这笔流水中的身份是什么？'),
                                  DropdownButtonFormField<String>(
                                    key: ValueKey('legacy-role-$name'),
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: '选择人员身份',
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'participant',
                                        child: Text(_type == 1 ? '收款人' : '承担人'),
                                      ),
                                      if (_type == 0)
                                        const DropdownMenuItem(
                                          value: 'payer',
                                          child: Text('付款人'),
                                        ),
                                      if (_type == 0)
                                        const DropdownMenuItem(
                                          value: 'both',
                                          child: Text('同时承担和付款'),
                                        ),
                                    ],
                                    onChanged: widget.busy
                                        ? null
                                        : (value) {
                                            if (![
                                              'participant',
                                              'payer',
                                              'both',
                                            ].contains(value)) {
                                              return;
                                            }
                                            setState(() {
                                              if (value != 'payer') {
                                                _personMatches.add(
                                                  AiPersonMatch(
                                                    sourceName: name,
                                                    role: 'participant',
                                                  ),
                                                );
                                              }
                                              if (value != 'participant') {
                                                _personMatches.add(
                                                  AiPersonMatch(
                                                    sourceName: name,
                                                    role: 'payer',
                                                  ),
                                                );
                                                _paymentMode = 'UNKNOWN';
                                                _payer = null;
                                              }
                                              _unresolved.remove(name);
                                            });
                                            _changed();
                                          },
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: widget.busy
                                          ? null
                                          : () {
                                              setState(() {
                                                _unresolved.remove(name);
                                              });
                                              _changed();
                                            },
                                      child: Text('忽略$name'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        TransactionFieldError(message: _unknownError),
                        if (_type == 0 &&
                            _participantScope == 'UNKNOWN' &&
                            _people.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: widget.busy
                                  ? null
                                  : _confirmParticipantSnapshot,
                              child: const Text('按当前名单确认承担人员'),
                            ),
                          ),
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
                              _participantScope = 'SPECIFIED';
                              _fieldSources['participants'] = 'USER';
                              _clearIssues(['participants']);
                            });
                            _changed();
                          },
                        ),
                        TransactionFieldError(message: _peopleError),
                        if (_type == 0) ...[
                          const SizedBox(height: 12),
                          Text('付款方式', key: _paymentAnchor),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('个人垫付'),
                                selected: _paymentMode == 'PERSON_PAID',
                                onSelected: widget.busy
                                    ? null
                                    : (_) => _selectPaymentMode('PERSON_PAID'),
                              ),
                              ChoiceChip(
                                label: const Text('共同钱包'),
                                selected: _paymentMode == 'SHARED_POOL',
                                onSelected: widget.busy
                                    ? null
                                    : (_) => _selectPaymentMode('SHARED_POOL'),
                              ),
                            ],
                          ),
                          TransactionFieldError(message: _paymentError),
                          if (_paymentMode == 'PERSON_PAID') ...[
                            const SizedBox(height: 8),
                            const Text('选择付款人；付款人不会自动加入承担人员。'),
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
                                _selectPayer(id);
                              },
                            ),
                          ],
                        ],
                        if (_splitMode == 'EQUAL')
                          TransactionSplitSummary(
                            compact: true,
                            peopleConfirmed:
                                _unresolved.isEmpty && _pendingMatches.isEmpty,
                            paymentConfirmed:
                                _type == 1 ||
                                (_paymentMode == 'SHARED_POOL' ||
                                    (_paymentMode == 'PERSON_PAID' &&
                                        _payer != null)),
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
                          )
                        else if (_splitMode != 'EQUAL') ...[
                          const Text('原文可能包含非等额分摊，不能按原方案直接记账。'),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: widget.busy
                                ? null
                                : () {
                                    setState(() {
                                      _splitMode = 'EQUAL';
                                      _fieldSources['splitMode'] = 'USER';
                                      _clearIssues(['splitMode']);
                                    });
                                    _changed();
                                  },
                            child: const Text('我确认改为等额分摊'),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_showSection('note'))
                  _section(
                    '备注',
                    TextField(
                      key: _noteAnchor,
                      controller: _note,
                      enabled: !widget.busy,
                      maxLines: 2,
                      onChanged: (_) {
                        _fieldSources['note'] = 'USER';
                        _changed();
                      },
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
