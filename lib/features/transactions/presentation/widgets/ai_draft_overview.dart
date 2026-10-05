import 'package:flutter/material.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/models/person.dart';
import '../../../../core/services/ai_draft_queue.dart';
import '../../../../core/services/ai_draft_readiness.dart';

class AiDraftOverview extends StatelessWidget {
  const AiDraftOverview({
    super.key,
    required this.items,
    required this.selectedUuid,
    required this.ledger,
    required this.people,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.busy,
    required this.failedUuids,
    required this.onSelect,
  });

  final List<AiDraftItem> items;
  final String? selectedUuid;
  final Ledger ledger;
  final List<Person> people;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final bool busy;
  final Set<String> failedUuids;
  final ValueChanged<String> onSelect;

  String _status(AiDraftItem item) {
    if (busy && item.uuid == selectedUuid) return '保存中';
    if (failedUuids.contains(item.uuid)) return '保存失败';
    final draft = item.draft;
    final blockers = aiDraftBlockingFields(
      draft,
      activePersonIds: people.map((person) => person.uuid).toSet(),
      categories: draft.type == 1 ? incomeCategories : expenseCategories,
      supportedCurrencies: supportedCurrenciesForLedger(ledger),
      today: DateTime.now(),
      amountInput: item.amountInput,
    );
    return blockers.isEmpty ? '可确认' : '待补充';
  }

  String _amount(AiDraftItem item) {
    final raw = item.amountInput?.trim();
    final amount = raw == null ? item.draft.amount : double.tryParse(raw);
    if (amount == null || !amount.isFinite || amount <= 0) return '金额待核对';
    return formatMoney(item.draft.currencyCode, amount);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty || (items.length < 2 && items.first.total < 2)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: Text(
            '本批 ${items.first.total} 笔 · 剩余 ${items.length} 笔',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SizedBox(
          height: 108,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final selected = item.uuid == selectedUuid;
              final status = _status(item);
              final colorScheme = Theme.of(context).colorScheme;
              return Semantics(
                button: true,
                selected: selected,
                label:
                    '第 ${item.position} 笔，${item.draft.categorySuggestion ?? '未分类'}，${_amount(item)}，$status',
                child: Material(
                  color: selected
                      ? colorScheme.secondaryContainer
                      : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: ValueKey('ai-draft-overview-${item.uuid}'),
                    onTap: busy ? null : () => onSelect(item.uuid),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 156,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? colorScheme.secondary
                              : colorScheme.outlineVariant,
                          width: selected ? 1.4 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '第 ${item.position} 笔',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 18,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.draft.note?.trim().isNotEmpty == true
                                ? item.draft.note!.trim()
                                : item.draft.sourceText ??
                                      item.draft.categorySuggestion ??
                                      '未命名事项',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _amount(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                status,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: status == '保存失败'
                                          ? colorScheme.error
                                          : colorScheme.onSurfaceVariant,
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
            },
          ),
        ),
      ],
    );
  }
}
