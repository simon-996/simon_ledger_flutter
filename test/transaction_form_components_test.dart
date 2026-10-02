import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/core/widgets/currency_widgets.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_form_components.dart';

void main() {
  for (final width in [320.0, 900.0]) {
    for (final currencies in const [
      ['CNY'],
      ['CNY', 'USD'],
      ['CNY', 'USD', 'EUR', 'GBP'],
      ['CNY', 'USD', 'EUR', 'GBP', 'JPY'],
    ]) {
      testWidgets(
        'amount and currency controls align at width $width with ${currencies.length} currencies',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 650));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final amountKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: TransactionResponsivePair(
                  breakpoint: 0,
                  first: SizedBox(
                    key: amountKey,
                    height: 58,
                    child: const TextField(
                      decoration: InputDecoration(labelText: '金额'),
                    ),
                  ),
                  second: CurrencySelector(
                    currencies: currencies,
                    selectedCurrency: 'CNY',
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final amount = tester.getRect(find.byKey(amountKey));
          final selector = tester.getRect(find.byType(CurrencySelector));
          expect(selector.top, closeTo(amount.top, 0.01));
          expect(selector.bottom, closeTo(amount.bottom, 0.01));
          final visual = currencies.length == 1
              ? find.byType(CurrencyLabel)
              : find
                    .byKey(const ValueKey('currency-picker'))
                    .evaluate()
                    .isNotEmpty
              ? find.byKey(const ValueKey('currency-picker'))
              : find.byKey(const ValueKey('currency-option-CNY'));
          expect(tester.getCenter(visual).dy, closeTo(amount.center.dy, 0.01));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('compact four currency selector preserves readable options', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = 'CNY';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrencySelector(
            currencies: const ['CNY', 'USD', 'EUR', 'GBP'],
            selectedCurrency: selected,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('currency-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('欧元'));
    await tester.pumpAndSettle();
    expect(selected, 'EUR');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'currency flags use union and regional flags with unknown fallback',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CurrencyLabel(code: 'EUR'),
                CurrencyLabel(code: 'HKD'),
                CurrencyLabel(code: 'MOP'),
                CurrencyLabel(code: 'TWD'),
                CurrencyLabel(code: 'ZZZ'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CountryFlag>(find.byType(CountryFlag))
            .map((flag) => flag.flagCode),
        ['eu', 'hk', 'mo', 'tw'],
      );
      expect(find.textContaining('ZZZ'), findsOneWidget);
      expect(find.byIcon(Icons.currency_exchange_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('one currency is an informative static label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrencySelector(
            currencies: const ['CNY'],
            selectedCurrency: 'CNY',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('人民币'), findsOneWidget);
    expect(tester.widget<CountryFlag>(find.byType(CountryFlag)).flagCode, 'cn');
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('many currencies can be searched without horizontal scrolling', (
    tester,
  ) async {
    String selected = 'CNY';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrencySelector(
            currencies: const ['CNY', 'USD', 'EUR', 'JPY', 'GBP'],
            selectedCurrency: selected,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('currency-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'GBP');
    await tester.pumpAndSettle();
    final flag = find.byType(CountryFlag);
    expect(tester.widget<CountryFlag>(flag.last).flagCode, 'gb');
    expect(
      tester.getCenter(flag.last).dx,
      lessThan(tester.getCenter(find.textContaining('英镑')).dx),
    );
    await tester.tap(find.textContaining('英镑'));
    await tester.pumpAndSettle();
    expect(selected, 'GBP');
  });

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

  testWidgets('category selector exposes a custom category action', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: CategorySelector(
            categories: const ['餐饮', '交通'],
            selectedCategory: '餐饮',
            isIncome: false,
            onChanged: (_) {},
            onAddCategory: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('category-option-add')));

    expect(tapped, isTrue);
  });
}
