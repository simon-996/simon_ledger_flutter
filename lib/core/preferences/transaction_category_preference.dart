import 'package:shared_preferences/shared_preferences.dart';

class TransactionCategoryPreference {
  const TransactionCategoryPreference._();

  static const expenseKey = 'transaction_categories.expense.v1';
  static const incomeKey = 'transaction_categories.income.v1';

  static const defaultExpenseCategories = [
    '默认',
    '交通',
    '购物',
    '餐饮',
    '杂费',
    '娱乐',
    '居住',
  ];
  static const defaultIncomeCategories = ['默认', '工资', '兼职', '理财', '红包', '其他'];

  static Future<TransactionCategorySet> read() async {
    final prefs = await SharedPreferences.getInstance();
    return TransactionCategorySet(
      expense: _merge(
        defaultExpenseCategories,
        prefs.getStringList(expenseKey),
      ),
      income: _merge(defaultIncomeCategories, prefs.getStringList(incomeKey)),
    );
  }

  static Future<TransactionCategorySet> addCategory({
    required int transactionType,
    required String category,
  }) async {
    final normalized = category.trim();
    if (normalized.isEmpty) {
      return read();
    }

    final prefs = await SharedPreferences.getInstance();
    final key = transactionType == 1 ? incomeKey : expenseKey;
    final defaults = transactionType == 1
        ? defaultIncomeCategories
        : defaultExpenseCategories;
    final custom = prefs.getStringList(key) ?? const [];
    final merged = _merge(defaults, custom);
    if (!merged.contains(normalized)) {
      final nextCustom = _merge(const [], [...custom, normalized]);
      await prefs.setStringList(key, nextCustom);
    }
    return read();
  }

  static List<String> _merge(
    List<String> defaults,
    List<String>? customCategories,
  ) {
    final values = <String>[];
    for (final raw in [...defaults, ...?customCategories]) {
      final value = raw.trim();
      if (value.isEmpty || values.contains(value)) continue;
      values.add(value);
    }
    return values;
  }
}

class TransactionCategorySet {
  const TransactionCategorySet({required this.expense, required this.income});

  final List<String> expense;
  final List<String> income;
}
