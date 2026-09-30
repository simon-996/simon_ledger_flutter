import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/utils/transaction_date.dart';

void main() {
  test('seven days includes today and six prior dates, excludes future', () {
    final range = TransactionDateRange.week(DateTime(2026, 1, 3, 12));
    expect(range.contains(DateTime(2025, 12, 28)), isTrue);
    expect(range.contains(DateTime(2026, 1, 3, 23, 59)), isTrue);
    expect(range.contains(DateTime(2025, 12, 27, 23, 59)), isFalse);
    expect(range.contains(DateTime(2026, 1, 4)), isFalse);
    expect(range.previous.start, DateTime(2025, 12, 21));
    expect(range.previous.end, DateTime(2025, 12, 27));
  });

  test('month comparisons preserve calendar boundaries across leap years', () {
    final range = TransactionDateRange.month(DateTime(2024, 3, 21));
    expect(range.start, DateTime(2024, 3, 1));
    expect(range.end, DateTime(2024, 3, 31));
    expect(range.previous.start, DateTime(2024, 2, 1));
    expect(range.previous.end, DateTime(2024, 2, 29));
    final year = TransactionDateRange.year(DateTime(2024, 2, 29));
    expect(year.previous.end, DateTime(2023, 12, 31));
  });

  test(
    'custom date end is inclusive and previous window has same day count',
    () {
      final range = TransactionDateRange.custom(
        DateTime(2026, 9, 3, 12),
        DateTime(2026, 9, 5, 9),
      );
      expect(range.contains(DateTime(2026, 9, 5, 23, 59, 59)), isTrue);
      expect(range.contains(DateTime(2026, 9, 6)), isFalse);
      expect(range.previous.start, DateTime(2026, 8, 31));
      expect(range.previous.end, DateTime(2026, 9, 2));
    },
  );

  test('day groups sort descending and total each converted record once', () {
    TransactionRecord record(
      String id,
      DateTime date,
      int type,
      double amount,
    ) => TransactionRecord()
      ..uuid = id
      ..createdAt = date
      ..type = type
      ..amount = amount;
    final groups = groupTransactionsByDay([
      record('a', DateTime(2025, 1, 1, 9), 0, 4),
      record('b', DateTime(2026, 1, 1, 10), 1, 5),
      record('c', DateTime(2025, 1, 1, 12), 0, 3),
    ], amountOf: (t) => t.amount * 7);
    expect(groups.map((g) => g.date), [
      DateTime(2026, 1, 1),
      DateTime(2025, 1, 1),
    ]);
    expect(groups.last.transactions.map((t) => t.uuid), ['c', 'a']);
    expect(groups.last.expense, 49);
    expect(groups.first.income, 35);
    expect(
      transactionDayLabel(DateTime(2026, 1, 2), DateTime(2026, 1, 2)),
      '今天',
    );
    expect(
      transactionDayLabel(DateTime(2026, 1, 1), DateTime(2026, 1, 2)),
      '昨天',
    );
    expect(
      transactionDayLabel(DateTime(2025, 1, 1), DateTime(2026, 1, 2)),
      '2025年1月1日',
    );
    expect(
      transactionRowDate(DateTime(2025, 1, 1, 9), DateTime(2026, 1, 2)),
      '2025-01-01 09:00',
    );
  });

  test('comparison handles missing history and zero baseline explicitly', () {
    expect(
      PeriodComparison(current: 20, previous: 0, previousCount: 0).label('CNY'),
      contains('无上期记录'),
    );
    final zero = PeriodComparison(current: 20, previous: 0, previousCount: 2);
    expect(zero.percent, isNull);
    expect(zero.label('CNY'), contains('上期为零'));
    final regular = PeriodComparison(
      current: 75,
      previous: 100,
      previousCount: 1,
    );
    expect(regular.percent, -25);
    expect(regular.difference, -25);
    expect(regular.label('CNY'), contains('减少 25.0%'));
  });
}
