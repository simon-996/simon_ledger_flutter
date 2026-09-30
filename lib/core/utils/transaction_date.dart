import '../models/money.dart';
import '../models/transaction_record.dart';

DateTime transactionDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

enum _DateRangeKind { rolling, month, year }

/// Inclusive local calendar dates. The exclusive bound avoids losing records
/// late on the end date and calendar arithmetic avoids DST duration drift.
class TransactionDateRange {
  TransactionDateRange._(this.start, this.end, this._kind);

  factory TransactionDateRange.custom(DateTime start, DateTime end) {
    final first = transactionDay(start);
    final last = transactionDay(end);
    if (last.isBefore(first)) throw ArgumentError('End precedes start');
    return TransactionDateRange._(first, last, _DateRangeKind.rolling);
  }

  factory TransactionDateRange.week(DateTime now) {
    final today = transactionDay(now);
    return TransactionDateRange._(
      DateTime(today.year, today.month, today.day - 6),
      today,
      _DateRangeKind.rolling,
    );
  }

  factory TransactionDateRange.month(DateTime date) => TransactionDateRange._(
    DateTime(date.year, date.month),
    DateTime(date.year, date.month + 1, 0),
    _DateRangeKind.month,
  );

  factory TransactionDateRange.year(DateTime date) => TransactionDateRange._(
    DateTime(date.year),
    DateTime(date.year, 12, 31),
    _DateRangeKind.year,
  );

  final DateTime start;
  final DateTime end;
  final _DateRangeKind _kind;

  bool contains(DateTime date) {
    final local = date.toLocal();
    return !local.isBefore(start) &&
        local.isBefore(DateTime(end.year, end.month, end.day + 1));
  }

  int get dayCount =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;

  TransactionDateRange get previous => switch (_kind) {
    _DateRangeKind.month => TransactionDateRange.month(
      DateTime(start.year, start.month - 1),
    ),
    _DateRangeKind.year => TransactionDateRange.year(DateTime(start.year - 1)),
    _DateRangeKind.rolling => TransactionDateRange.custom(
      DateTime(start.year, start.month, start.day - dayCount),
      DateTime(start.year, start.month, start.day - 1),
    ),
  };

  String get label => '${_dateLabel(start)} – ${_dateLabel(end)}';
}

String _dateLabel(DateTime date) => '${date.year}/${date.month}/${date.day}';

String transactionDayLabel(DateTime date, DateTime now) {
  final day = transactionDay(date);
  final today = transactionDay(now);
  if (day == today) return '今天';
  if (day == DateTime(today.year, today.month, today.day - 1)) return '昨天';
  return '${day.year == today.year ? '' : '${day.year}年'}${day.month}月${day.day}日';
}

String transactionRowDate(DateTime date, DateTime now) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final year = local.year == now.toLocal().year ? '' : '${local.year}-';
  return '$year${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class TransactionDayGroup {
  TransactionDayGroup(this.date, this.transactions, this.expense, this.income);
  final DateTime date;
  final List<TransactionRecord> transactions;
  final double expense;
  final double income;
}

List<TransactionDayGroup> groupTransactionsByDay(
  List<TransactionRecord> records, {
  required double Function(TransactionRecord) amountOf,
}) {
  final grouped = <DateTime, List<TransactionRecord>>{};
  for (final record in records) {
    (grouped[transactionDay(record.createdAt)] ??= []).add(record);
  }
  final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return dates.map((day) {
    final rows = grouped[day]!
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    var expense = 0.0;
    var income = 0.0;
    for (final row in rows) {
      final amount = amountOf(row);
      if (row.type == 0) expense += amount;
      if (row.type == 1) income += amount;
    }
    return TransactionDayGroup(day, rows, expense, income);
  }).toList();
}

class PeriodComparison {
  const PeriodComparison({
    required this.current,
    required this.previous,
    required this.previousCount,
  });
  final double current;
  final double previous;
  final int previousCount;
  double get difference => current - previous;
  double? get percent => previousCount == 0 || previous == 0
      ? null
      : difference / previous.abs() * 100;
  String label(String currency) {
    if (previousCount == 0) return '无上期记录';
    final delta = formatMoney(currency, difference.abs());
    final direction = difference >= 0 ? '增加' : '减少';
    if (previous == 0) return '上期为零 · $direction $delta';
    if (difference == 0) return '与上期持平 · ${formatMoney(currency, 0)}';
    return '较上期$direction ${percent!.abs().toStringAsFixed(1)}% · $direction $delta';
  }
}
