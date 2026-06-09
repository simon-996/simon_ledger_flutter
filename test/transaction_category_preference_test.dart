import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/preferences/transaction_category_preference.dart';

void main() {
  test('category preference merges defaults and custom categories', () async {
    SharedPreferences.setMockInitialValues({
      TransactionCategoryPreference.expenseKey: ['咖啡', '餐饮', ''],
      TransactionCategoryPreference.incomeKey: ['奖金'],
    });

    final categories = await TransactionCategoryPreference.read();

    expect(categories.expense, containsAll(['默认', '餐饮', '咖啡']));
    expect(categories.expense.where((item) => item == '餐饮'), hasLength(1));
    expect(categories.expense, isNot(contains('')));
    expect(categories.income, containsAll(['默认', '工资', '奖金']));
  });

  test('addCategory persists custom categories by transaction type', () async {
    SharedPreferences.setMockInitialValues({});

    await TransactionCategoryPreference.addCategory(
      transactionType: 0,
      category: '咖啡',
    );
    await TransactionCategoryPreference.addCategory(
      transactionType: 1,
      category: '奖金',
    );

    final categories = await TransactionCategoryPreference.read();
    expect(categories.expense, contains('咖啡'));
    expect(categories.income, contains('奖金'));
    expect(categories.income, isNot(contains('咖啡')));
  });

  test('recent categories are ordered first by transaction type', () async {
    SharedPreferences.setMockInitialValues({});

    await TransactionCategoryPreference.markRecentlyUsed(
      transactionType: 0,
      category: '餐饮',
    );
    await TransactionCategoryPreference.markRecentlyUsed(
      transactionType: 0,
      category: '交通',
    );
    await TransactionCategoryPreference.markRecentlyUsed(
      transactionType: 1,
      category: '工资',
    );

    final categories = await TransactionCategoryPreference.read();

    expect(categories.expense.take(2), ['交通', '餐饮']);
    expect(categories.income.first, '工资');
    expect(categories.income, isNot(contains('交通')));
  });
}
