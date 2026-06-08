import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_form_components.dart';

void main() {
  testWidgets('transaction form options use tonal fills without borders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TransactionTypeSelector(selectedType: 0, onChanged: (_) {}),
                PaymentModePanel(
                  paidByPerson: false,
                  description: '共同承担',
                  onChanged: (_) {},
                ),
                CurrencySelector(
                  currencies: const ['CNY', 'USD'],
                  selectedCurrency: 'CNY',
                  onChanged: (_) {},
                ),
                CategorySelector(
                  categories: const ['餐饮', '交通'],
                  selectedCategory: '餐饮',
                  isIncome: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final key in const [
      ValueKey('transaction-type-option-0'),
      ValueKey('transaction-type-option-1'),
      ValueKey('payment-mode-option-共同钱包'),
      ValueKey('payment-mode-option-某人代付'),
      ValueKey('currency-option-CNY'),
      ValueKey('currency-option-USD'),
      ValueKey('category-option-餐饮'),
      ValueKey('category-option-交通'),
    ]) {
      final option = tester.widget<AnimatedContainer>(find.byKey(key));
      final decoration = option.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    }
  });
}
