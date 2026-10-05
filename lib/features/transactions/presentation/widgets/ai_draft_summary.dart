import 'package:flutter/material.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/services/ai_draft_queue.dart';
import '../../../../core/services/ai_draft_readiness.dart';

class AiDraftSummary extends StatefulWidget {
  const AiDraftSummary({
    super.key,
    required this.item,
    required this.ledger,
    required this.people,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.busy,
    required this.onEdit,
    required this.onConfirm,
    required this.onSkip,
  });

  final AiDraftItem item;
  final Ledger ledger;
  final List<Person> people;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final bool busy;
  final ValueChanged<String> onEdit;
  final Future<void> Function() onConfirm;
  final VoidCallback onSkip;

  @override
  State<AiDraftSummary> createState() => _AiDraftSummaryState();
}

class _AiDraftSummaryState extends State<AiDraftSummary> {
  bool _showOriginal = false;

  AiDraft get _draft => widget.item.draft;

  List<String> get _categories =>
      _draft.type == 1 ? widget.incomeCategories : widget.expenseCategories;

  List<String> get _blockers => aiDraftBlockingFields(
    _draft,
    activePersonIds: widget.people.map((person) => person.uuid).toSet(),
    categories: _categories,
    supportedCurrencies: supportedCurrenciesForLedger(widget.ledger),
    today: DateTime.now(),
    amountInput: widget.item.amountInput,
  );

  String get _amountLabel {
    final raw = widget.item.amountInput?.trim();
    final amount = raw == null ? _draft.amount : double.tryParse(raw);
    if (amount == null || !amount.isFinite || amount <= 0) return '金额待核对';
    return formatMoney(_draft.currencyCode, amount);
  }

  String get _dateLabel {
    final date = _draft.happenedAt;
    if (date == null) return '待选择日期';
    final local = date.toLocal();
    final day = DateUtils.dateOnly(local);
    final ymd =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final formatted = _draft.datePrecision != 'TIME'
        ? ymd
        : '$ymd ${local.hour.toString().padLeft(2, '0')}:'
              '${local.minute.toString().padLeft(2, '0')}';
    return _draft.fieldSources['happenedAt'] == 'DEFAULT'
        ? '$formatted · 默认日期'
        : formatted;
  }

  String get _typeLabel => switch (_draft.type) {
    0 => '支出',
    1 => '收入',
    _ => '待确认收支类型',
  };

  String get _payerLabel {
    if (_draft.type == 1) return '无需付款';
    if (_draft.paymentMode == 'SHARED_POOL') return '共同钱包';
    if (_draft.paymentMode != 'PERSON_PAID') return '待选择付款方式';
    final payer = widget.people
        .where((person) => person.uuid == _draft.payerPersonUuid)
        .firstOrNull;
    return payer == null ? '待选择付款人' : '${payer.name}垫付';
  }

  String get _participantsLabel {
    if (_draft.participantScope == 'UNKNOWN') return '待确认承担人员';
    final names = _draft.personUuids
        .map(
          (uuid) => widget.people
              .where((person) => person.uuid == uuid)
              .firstOrNull
              ?.name,
        )
        .whereType<String>()
        .toList();
    if (_draft.participantScope == 'ALL') {
      final allPeopleCount = widget.people.length;
      return names.length == allPeopleCount
          ? '全体 $allPeopleCount 人承担'
          : '全体 $allPeopleCount 人中 ${names.length} 人承担';
    }
    if (names.isEmpty) return '待选择承担人员';
    return names.length == 1 ? '${names.single}承担' : '${names.join('、')}承担';
  }

  String? get _splitLabel {
    if (_draft.splitMode != 'EQUAL') return '原文包含非等额分摊 · 需处理';
    if (_draft.personUuids.isEmpty) return null;
    final raw = widget.item.amountInput?.trim();
    final amount = raw == null ? _draft.amount : double.tryParse(raw);
    if (amount == null || !amount.isFinite || amount <= 0) return null;
    final perPerson = formatMoney(
      _draft.currencyCode,
      amount / _draft.personUuids.length,
    );
    final prefix = _draft.fieldSources['splitMode'] == 'USER' ? '' : '默认';
    return '$prefix均摊 · 约 $perPerson/人';
  }

  String _blockerLabel(String field) => switch (field) {
    'amount' => '确认金额',
    'type' => '确认收支类型',
    'currencyCode' => '选择支持的币种',
    'category' => '选择有效分类',
    'participants' => '确认承担人员',
    'payer' => '选择付款人',
    'paymentMode' => '选择付款方式',
    'splitMode' => '确认分摊方式',
    'happenedAt' => '确认发生日期',
    'legacy' => '复核旧草稿中的人员角色',
    'excludedParticipants' => '确认排除人员',
    _ => '核对$field信息',
  };

  @override
  Widget build(BuildContext context) {
    final blockers = _blockers;
    final colorScheme = Theme.of(context).colorScheme;
    final source = _draft.sourceText?.trim();
    final canConfirm = blockers.isEmpty && !widget.busy;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '第 ${widget.item.position}/${widget.item.total} 笔',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: widget.item.position / widget.item.total,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  key: const ValueKey('ai-summary-edit-category'),
                  onTap: widget.busy ? null : () => widget.onEdit('category'),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _draft.categorySuggestion ?? '待选择分类',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_typeLabel),
                const SizedBox(height: 8),
                InkWell(
                  key: const ValueKey('ai-summary-edit-amount'),
                  onTap: widget.busy ? null : () => widget.onEdit('amount'),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _amountLabel,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _amountLabel == '金额待核对'
                                ? colorScheme.error
                                : colorScheme.onSurface,
                          ),
                    ),
                  ),
                ),
                if (_draft.categoryOriginalSuggestion?.isNotEmpty == true &&
                    _draft.categoryOriginalSuggestion !=
                        _draft.categorySuggestion) ...[
                  const SizedBox(height: 4),
                  Text(
                    '根据“${_draft.categoryOriginalSuggestion}”建议',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                _summaryField(
                  context,
                  field: 'happenedAt',
                  label: '日期',
                  value: _dateLabel,
                ),
                _summaryField(
                  context,
                  field: _draft.type == 0 ? 'paymentMode' : 'participants',
                  label: _draft.type == 0 ? '付款方式' : '收入归属',
                  value: _draft.type == 0 ? _payerLabel : _participantsLabel,
                ),
                if (_draft.type == 0) ...[
                  _summaryField(
                    context,
                    field: 'participants',
                    label: '承担人员',
                    value: _participantsLabel,
                  ),
                  if (_splitLabel != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Text(
                        _splitLabel!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
                if (_draft.note?.trim().isNotEmpty == true)
                  _summaryField(
                    context,
                    field: 'note',
                    label: '备注',
                    value: _draft.note!.trim(),
                    multiline: true,
                  ),
                if (source != null && source.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showOriginal = !_showOriginal),
                    icon: Icon(
                      _showOriginal
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(_showOriginal ? '收起原文' : '查看原文'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  if (_showOriginal)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Text(source),
                    ),
                ],
                if (blockers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.46),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.error.withValues(alpha: 0.22),
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '还有 ${blockers.length} 项待确认',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        for (final field in blockers)
                          TextButton.icon(
                            key: ValueKey('ai-summary-issue-$field'),
                            onPressed: widget.busy
                                ? null
                                : () => widget.onEdit(field),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(_blockerLabel(field)),
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
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
                  onPressed: canConfirm ? widget.onConfirm : null,
                  child: Text(widget.busy ? '保存中' : '确认记账'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryField(
    BuildContext context, {
    required String field,
    required String label,
    required String value,
    bool multiline = false,
  }) => InkWell(
    key: ValueKey('ai-summary-edit-$field'),
    onTap: widget.busy ? null : () => widget.onEdit(field),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
          const SizedBox(width: 8),
          Icon(
            Icons.edit_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    ),
  );
}
