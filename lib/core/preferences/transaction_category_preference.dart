import 'package:shared_preferences/shared_preferences.dart';

class TransactionCategoryPreference {
  const TransactionCategoryPreference._();

  static const expenseKey = 'transaction_categories.expense.v1';
  static const incomeKey = 'transaction_categories.income.v1';
  static const recentExpenseKey = 'transaction_categories.recent_expense.v1';
  static const recentIncomeKey = 'transaction_categories.recent_income.v1';
  static const _maxRecentCount = 5;

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
    final expenseBase = _merge(
      defaultExpenseCategories,
      prefs.getStringList(expenseKey),
    );
    final incomeBase = _merge(
      defaultIncomeCategories,
      prefs.getStringList(incomeKey),
    );
    return TransactionCategorySet(
      expense: _orderByRecent(
        expenseBase,
        prefs.getStringList(recentExpenseKey),
      ),
      income: _orderByRecent(incomeBase, prefs.getStringList(recentIncomeKey)),
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
    final recentKey = _recentKey(transactionType);
    final defaults = transactionType == 1
        ? defaultIncomeCategories
        : defaultExpenseCategories;
    final custom = prefs.getStringList(key) ?? const [];
    final merged = _merge(defaults, custom);
    if (!merged.contains(normalized)) {
      final nextCustom = _merge(const [], [...custom, normalized]);
      await prefs.setStringList(key, nextCustom);
    }
    await _writeRecent(prefs, recentKey, normalized);
    return read();
  }

  static Future<TransactionCategorySet> markRecentlyUsed({
    required int transactionType,
    required String category,
  }) async {
    final normalized = category.trim();
    if (normalized.isEmpty) {
      return read();
    }

    final prefs = await SharedPreferences.getInstance();
    await _writeRecent(prefs, _recentKey(transactionType), normalized);
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

  static List<String> _orderByRecent(
    List<String> baseCategories,
    List<String>? recentCategories,
  ) {
    final recent = _merge(const [], recentCategories);
    final values = <String>[];
    for (final category in [...recent, ...baseCategories]) {
      if (values.contains(category)) continue;
      values.add(category);
    }
    return values;
  }

  static Future<void> _writeRecent(
    SharedPreferences prefs,
    String key,
    String category,
  ) async {
    final next = _merge(const [], [
      category,
      ...(prefs.getStringList(key) ?? const []),
    ]).take(_maxRecentCount).toList();
    await prefs.setStringList(key, next);
  }

  static String _recentKey(int transactionType) {
    return transactionType == 1 ? recentIncomeKey : recentExpenseKey;
  }
}

class TransactionCategorySet {
  const TransactionCategorySet({required this.expense, required this.income});

  final List<String> expense;
  final List<String> income;
}
