import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_split_summary.dart';

Ledger book([double rate = 7.2, String code = 'USD']) => Ledger()
  ..uuid = 'split-test'
  ..name = '旅行'
  ..baseCurrencyCode = code
  ..exchangeRateToCNY = rate;

Future<void> mount(
  WidgetTester tester,
  TransactionSplitSummary summary, {
  double width = 390,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: summary),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reverse conversion and income each round only for display', (
    tester,
  ) async {
    await mount(
      tester,
      TransactionSplitSummary(
        type: 1,
        amount: 720,
        currency: 'cny',
        participantCount: 3,
        ledger: book(),
      ),
    );
    expect(find.text('收入分配 · 3 人收款'), findsOneWidget);
    expect(find.text('总额 CNY 720.00'), findsOneWidget);
    expect(find.text('每人 CNY 240.00'), findsOneWidget);
    expect(find.text('总额 ≈ USD 100.00'), findsOneWidget);
    expect(find.text('每人 ≈ USD 33.33'), findsOneWidget);
  });
  testWidgets('CNY ledger has one currency and no people preserves total', (
    tester,
  ) async {
    await mount(
      tester,
      TransactionSplitSummary(
        type: 0,
        amount: 20,
        currency: 'CNY',
        participantCount: 0,
        ledger: book(double.nan, 'CNY'),
      ),
    );
    expect(find.byKey(const ValueKey('split-currency-CNY')), findsOneWidget);
    expect(find.text('总额 CNY 20.00'), findsOneWidget);
    expect(find.text('每人 CNY —'), findsOneWidget);
    expect(find.textContaining('≈'), findsNothing);
  });
  testWidgets('invalid values and rates do not invent converted amounts', (
    tester,
  ) async {
    for (final rate in [0.0, -1.0, double.nan, double.infinity]) {
      await mount(
        tester,
        TransactionSplitSummary(
          type: 0,
          amount: 20,
          currency: 'USD',
          participantCount: 2,
          ledger: book(rate),
        ),
      );
      expect(find.text('总额 USD 20.00'), findsOneWidget);
      expect(find.text('每人 USD 10.00'), findsOneWidget);
      expect(find.text('总额 ≈ CNY —'), findsOneWidget);
      expect(find.textContaining('无法换算'), findsOneWidget);
    }
    for (final value in [null, 0.0, -1.0, double.nan, double.infinity]) {
      await mount(
        tester,
        TransactionSplitSummary(
          type: 0,
          amount: value,
          currency: 'USD',
          participantCount: 2,
          ledger: book(),
        ),
      );
      expect(find.text('总额 USD —'), findsOneWidget);
      expect(find.text('每人 ≈ CNY —'), findsOneWidget);
    }
    await mount(
      tester,
      TransactionSplitSummary(
        type: 0,
        amount: 1e308,
        currency: 'USD',
        participantCount: 2,
        ledger: book(),
      ),
    );
    expect(find.text('总额 ≈ CNY —'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final (width, scale) in [(280.0, 1.5), (489.0, 1.0)]) {
    testWidgets('all currency amounts fit at $width / $scale', (tester) async {
      await mount(
        tester,
        TransactionSplitSummary(
          type: 0,
          amount: 123456789.12,
          currency: 'USD',
          participantCount: 2,
          payerName: '小王',
          ledger: book(),
        ),
        width: width,
        scale: scale,
      );
      for (final label in [
        '总额 USD 123456789.12',
        '每人 USD 61728394.56',
        '总额 ≈ CNY 888888881.66',
        '每人 ≈ CNY 444444440.83',
      ]) {
        final finder = find.text(label);
        expect(finder, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
          isFalse,
        );
        expect(tester.getRect(finder).right, lessThanOrEqualTo(width - 16));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
