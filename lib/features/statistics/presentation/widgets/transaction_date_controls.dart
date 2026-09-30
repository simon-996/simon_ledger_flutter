import 'package:flutter/material.dart';
import '../../../../core/utils/transaction_date.dart';

/// Calendar browsing is independent of presets, so a concrete month can be
/// revisited without losing the selected transaction type or currency.
class TransactionDateControls extends StatelessWidget {
  const TransactionDateControls({
    super.key,
    required this.month,
    this.customRange,
    required this.onMonthChanged,
    required this.onCustomChanged,
  });
  final DateTime month;
  final TransactionDateRange? customRange;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<TransactionDateRange> onCustomChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上个月',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
            padding: const EdgeInsets.all(4),
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                onMonthChanged(DateTime(month.year, month.month - 1)),
          ),
          Text(
            '${month.year}年${month.month}月',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          IconButton(
            tooltip: '下个月',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
            padding: const EdgeInsets.all(4),
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                onMonthChanged(DateTime(month.year, month.month + 1)),
          ),
        ],
      ),
      TextButton.icon(
        icon: const Icon(Icons.date_range_outlined, size: 18),
        label: const Text('自定义日期'),
        onPressed: () async {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime(1),
            lastDate: DateTime(9999, 12, 31),
            initialDateRange: DateTimeRange(
              start:
                  customRange?.start ?? TransactionDateRange.month(month).start,
              end: customRange?.end ?? TransactionDateRange.month(month).end,
            ),
            helpText: '选择日期范围（含起止日）',
            saveText: '应用',
          );
          if (range != null) {
            onCustomChanged(
              TransactionDateRange.custom(range.start, range.end),
            );
          }
        },
      ),
    ],
  );
}
