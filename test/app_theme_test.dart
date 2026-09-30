import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/widgets/share_ledger_image_widget.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_form_components.dart';

void main() {
  test('AppTheme uses a calm semantic color baseline', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;
    final colors = theme.extension<AppColors>()!;

    expect(AppPalette.primary, const Color(0xFF3F78A3));
    expect(AppColors.light.income, const Color(0xFF3F7F63));
    expect(AppColors.light.expense, const Color(0xFF9F6258));
    expect(colors.success, colors.income);
    expect(colors.info, scheme.primary);
    expect(scheme.tertiary, const Color(0xFF936B22));
    expect(scheme.error, const Color(0xFFC44747));
    expect(AppPalette.background, const Color(0xFFF5F5F7));
    expect(AppTheme.radiusLarge, 24);
    expect(theme.scaffoldBackgroundColor, AppPalette.background);
    expect(scheme.surfaceContainerLowest, Colors.white);
    expect(scheme.surfaceContainerLow, const Color(0xFFF9F9FB));
    expect(scheme.outlineVariant, const Color(0xFFE0E2E8));
    expect(theme.cardTheme.elevation, 0);
    expect(theme.navigationBarTheme.height, 70);
    expect(
      theme.navigationBarTheme.backgroundColor,
      Colors.white.withValues(alpha: 0.96),
    );
  });

  test('AppTheme keeps option controls tonal without visible borders', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;
    final chipTheme = theme.chipTheme;
    final segmentStyle = theme.segmentedButtonTheme.style!;
    final outlinedStyle = theme.outlinedButtonTheme.style!;

    expect(chipTheme.side, BorderSide.none);
    expect(chipTheme.backgroundColor, Colors.white);
    expect(chipTheme.selectedColor, AppPalette.primary.withValues(alpha: 0.13));
    expect(segmentStyle.side!.resolve(<WidgetState>{}), BorderSide.none);
    expect(
      segmentStyle.backgroundColor!.resolve(<WidgetState>{}),
      scheme.surfaceContainerHigh,
    );
    expect(
      segmentStyle.backgroundColor!.resolve(<WidgetState>{
        WidgetState.selected,
      }),
      Colors.white,
    );
    expect(
      outlinedStyle.side!.resolve(<WidgetState>{}),
      BorderSide(color: AppPalette.primary.withValues(alpha: 0.5)),
    );
    expect(outlinedStyle.backgroundColor, isNull);
  });

  test('AppTheme gives standard buttons visible pressed state layers', () {
    final theme = AppTheme.lightTheme;
    const pressed = <WidgetState>{WidgetState.pressed};

    expect(
      theme.filledButtonTheme.style!.overlayColor!.resolve(pressed),
      AppPalette.content.withValues(alpha: 0.1),
    );
    expect(
      theme.outlinedButtonTheme.style!.overlayColor!.resolve(pressed),
      AppPalette.primary.withValues(alpha: 0.14),
    );
    expect(
      theme.textButtonTheme.style!.overlayColor!.resolve(pressed),
      AppPalette.primary.withValues(alpha: 0.14),
    );
    expect(
      theme.iconButtonTheme.style!.overlayColor!.resolve(pressed),
      AppPalette.primary.withValues(alpha: 0.14),
    );
  });

  test('AppTheme uses calm floating surfaces for modals', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;

    expect(theme.bottomSheetTheme.backgroundColor, AppPalette.background);
    expect(theme.bottomSheetTheme.modalBackgroundColor, AppPalette.background);
    expect(
      theme.bottomSheetTheme.dragHandleColor,
      scheme.outlineVariant.withValues(alpha: 0.72),
    );
    final bottomSheetShape =
        theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
    final bottomSheetRadius = bottomSheetShape.borderRadius as BorderRadius;
    expect(bottomSheetRadius.topLeft.x, 32);
    expect(bottomSheetRadius.topRight.x, 32);

    expect(theme.dialogTheme.backgroundColor, AppPalette.background);
    final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
    final dialogRadius = dialogShape.borderRadius as BorderRadius;
    expect(dialogRadius.topLeft.x, 28);
    expect(dialogRadius.bottomRight.x, 28);
  });

  testWidgets('one theme override reaches forms, balances, and share images', (
    tester,
  ) async {
    final colors = AppColors.light.copyWith(
      income: const Color(0xFF305045),
      expense: const Color(0xFF804F50),
    );
    final base = AppTheme.lightTheme;
    final scheme = base.colorScheme.copyWith(
      onSurfaceVariant: const Color(0xFF5B6570),
    );
    final ledger = Ledger()
      ..uuid = 'palette-preview'
      ..name = '颜色预览'
      ..baseCurrencyCode = 'CNY';
    await tester.pumpWidget(
      MaterialApp(
        theme: base.copyWith(colorScheme: scheme, extensions: [colors]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TransactionTypeSelector(selectedType: 1, onChanged: (_) {}),
                const AppPersonBalanceCard(
                  avatar: '?',
                  name: '林',
                  balance: '42.00',
                  isPositive: true,
                ),
                const AppPersonBalanceCard(
                  avatar: '?',
                  name: '陈',
                  balance: '-18.00',
                  isPositive: false,
                ),
                ShareLedgerImageWidget(
                  ledger: ledger,
                  transactions: const [],
                  peoplePool: const [],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color? textColor(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    expect(textColor('收入'), colors.income);
    expect(textColor('42.00'), colors.income);
    expect(textColor('-18.00'), colors.expense);
    expect(textColor('总收入'), colors.income);
    expect(textColor('总支出'), colors.expense);
    expect(textColor('结余 (CNY)'), scheme.onSurfaceVariant);
  });

  testWidgets('notices follow overridden semantic colors', (tester) async {
    final colors = AppColors.light.copyWith(
      success: const Color(0xFF305045),
      info: const Color(0xFF395A73),
    );
    late BuildContext noticeContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(extensions: [colors]),
        home: Builder(
          builder: (context) {
            noticeContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    for (final notice in [
      (AppNoticeType.success, Icons.check_rounded, colors.success),
      (AppNoticeType.info, Icons.info_outline_rounded, colors.info),
      (
        AppNoticeType.error,
        Icons.error_outline_rounded,
        AppTheme.lightTheme.colorScheme.error,
      ),
    ]) {
      AppNotice.show(noticeContext, '提示', type: notice.$1);
      await tester.pumpAndSettle();
      expect(tester.widget<Icon>(find.byIcon(notice.$2)).color, notice.$3);
      AppNotice.dismiss();
      await tester.pump();
    }
  });

  test('category colors remain stable across ranking and custom palettes', () {
    final colors = AppColors.light;
    final categories = ['默认', '交通', '购物', '餐饮', '杂费', '娱乐', '居住'];
    final before = {
      for (final category in categories)
        category: colors.chartColorFor(category),
    };
    final after = {
      for (final category in categories.reversed)
        category: colors.chartColorFor(category),
    };
    expect(after, before);
    expect(before.values.toSet(), hasLength(categories.length));
    expect(colors.chartColorFor('自定义分类'), colors.chartColorFor(' 自定义分类 '));
    final custom = colors.copyWith(chartColors: [colors.income]);
    expect(custom.chartColorFor('餐饮'), colors.income);
    expect(custom.chartColorFor('自定义分类'), colors.income);
  });

  test('semantic colors and chart labels have readable contrast', () {
    final scheme = AppTheme.lightTheme.colorScheme;
    final colors = AppColors.light;
    double contrast(Color a, Color b) {
      final first = a.computeLuminance();
      final second = b.computeLuminance();
      return first > second
          ? (first + 0.05) / (second + 0.05)
          : (second + 0.05) / (first + 0.05);
    }

    for (final pair in [
      (scheme.primary, scheme.onPrimary),
      (scheme.tertiary, scheme.onTertiary),
      (scheme.error, scheme.onError),
      (colors.income, colors.onIncome),
      (colors.expense, colors.onExpense),
      (scheme.surfaceContainerLowest, scheme.onSurfaceVariant),
      for (final color in colors.chartColors)
        (color, AppColors.foregroundFor(color, scheme)),
    ]) {
      expect(
        contrast(pair.$1, pair.$2),
        greaterThanOrEqualTo(4.5),
        reason: '${pair.$1} on ${pair.$2}',
      );
    }
  });
}
