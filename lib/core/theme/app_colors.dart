import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Raw color values live here; widgets consume ColorScheme or AppColors.
abstract final class AppPalette {
  static const primary = Color(0xFF3F78A3);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFE8F1F7);
  static const onPrimaryContainer = Color(0xFF173A52);
  static const secondary = Color(0xFF6E7380);
  static const warning = Color(0xFF936B22);
  static const warningContainer = Color(0xFFF4EAD6);
  static const onWarningContainer = Color(0xFF584214);
  static const error = Color(0xFFC44747);
  static const errorContainer = Color(0xFFFBE9E7);
  static const onErrorContainer = Color(0xFF6B292A);
  static const income = Color(0xFF3F7F63);
  static const expense = Color(0xFF9F6258);
  static const background = Color(0xFFF5F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF9F9FB);
  static const surfaceMuted = Color(0xFFEDEEF2);
  static const surfaceStrong = Color(0xFFE3E5EA);
  static const content = Color(0xFF1D1D1F);
  static const disabledContent = Color(0xFF8A8F99);
  static const outline = Color(0xFFB8BCC6);
  static const divider = Color(0xFFE0E2E8);
  static const inversePrimary = Color(0xFFB4D5EB);

  static const chartColors = [
    primary,
    income,
    Color(0xFF927139),
    Color(0xFF7E6D94),
    Color(0xFF9B647C),
    Color(0xFF4C7F80),
    Color(0xFF667889),
    Color(0xFF956A4D),
    Color(0xFF707944),
  ];
}

/// Domain colors that have no standard Material ColorScheme role.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.income,
    required this.expense,
    required this.onIncome,
    required this.onExpense,
    required this.success,
    required this.info,
    required this.disabledContent,
    required List<Color> chartColors,
  }) : _chartColors = chartColors;

  static const light = AppColors(
    income: AppPalette.income,
    expense: AppPalette.expense,
    onIncome: AppPalette.onPrimary,
    onExpense: AppPalette.onPrimary,
    success: AppPalette.income,
    info: AppPalette.primary,
    disabledContent: AppPalette.disabledContent,
    chartColors: AppPalette.chartColors,
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  final Color income;
  final Color expense;
  final Color onIncome;
  final Color onExpense;
  final Color success;
  final Color info;
  final Color disabledContent;
  final List<Color> _chartColors;
  List<Color> get chartColors =>
      _chartColors.isEmpty ? AppPalette.chartColors : _chartColors;

  Color amount(bool isPositive) => isPositive ? income : expense;

  Color transaction(int type) => type == 1 ? income : expense;

  Color onTransaction(int type) => type == 1 ? onIncome : onExpense;

  // Keep built-in categories distinct within each transaction type.
  static const _categorySlots = {
    '默认': 8,
    '交通': 0,
    '购物': 3,
    '餐饮': 7,
    '杂费': 6,
    '娱乐': 4,
    '居住': 5,
    '工资': 1,
    '兼职': 0,
    '理财': 2,
    '红包': 4,
    '其他': 6,
  };

  /// Category color is independent of amount, rank, and time filter.
  Color chartColorFor(String category) {
    final key = category.trim();
    var slot = _categorySlots[key];
    if (slot == null) {
      var hash = 0;
      for (final rune in key.runes) {
        hash = (hash * 31 + rune) & 0x7fffffff;
      }
      slot = hash;
    }
    return chartColors[slot % chartColors.length];
  }

  static Color foregroundFor(Color background, ColorScheme scheme) {
    final luminance = background.computeLuminance();
    double contrast(Color foreground) {
      final other = foreground.computeLuminance();
      return (math.max(luminance, other) + 0.05) /
          (math.min(luminance, other) + 0.05);
    }

    return contrast(scheme.onPrimary) >= contrast(scheme.onSurface)
        ? scheme.onPrimary
        : scheme.onSurface;
  }

  @override
  AppColors copyWith({
    Color? income,
    Color? expense,
    Color? onIncome,
    Color? onExpense,
    Color? success,
    Color? info,
    Color? disabledContent,
    List<Color>? chartColors,
  }) => AppColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    onIncome: onIncome ?? this.onIncome,
    onExpense: onExpense ?? this.onExpense,
    success: success ?? this.success,
    info: info ?? this.info,
    disabledContent: disabledContent ?? this.disabledContent,
    chartColors: List.unmodifiable(chartColors ?? this.chartColors),
  );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null || t <= 0) return this;
    if (t >= 1) return other;
    return AppColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      onIncome: Color.lerp(onIncome, other.onIncome, t)!,
      onExpense: Color.lerp(onExpense, other.onExpense, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      disabledContent: Color.lerp(disabledContent, other.disabledContent, t)!,
      chartColors: List.unmodifiable(
        List.generate(
          math.max(chartColors.length, other.chartColors.length),
          (index) => Color.lerp(
            chartColors[index % chartColors.length],
            other.chartColors[index % other.chartColors.length],
            t,
          )!,
        ),
      ),
    );
  }
}
