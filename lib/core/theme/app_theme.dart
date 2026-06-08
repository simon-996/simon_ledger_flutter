import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF007AFF);
  static const Color secondaryColor = Color(0xFF6E7380);
  static const Color tertiaryColor = Color(0xFFFF9F0A);
  static const Color errorColor = Color(0xFFFF3B30);
  static const Color successColor = Color(0xFF34C759);
  static const Color infoColor = Color(0xFF64D2FF);

  static const Color surfaceColor = Color(0xFFF5F5F7);
  static const Color surfaceContainerColor = Color(0xFFFFFFFF);
  static const Color surfaceMutedColor = Color(0xFFEDEEF2);
  static const Color onSurfaceColor = Color(0xFF1D1D1F);

  static const List<Color> chartColors = [
    primaryColor,
    successColor,
    tertiaryColor,
    errorColor,
    Color(0xFF5E5CE6),
    infoColor,
    Color(0xFFFF2D55),
    Color(0xFFAF52DE),
    Color(0xFF30D158),
  ];

  static const double radiusSmall = 12;
  static const double radiusMedium = 18;
  static const double radiusLarge = 24;
  static const double radiusXLarge = 30;
  static const double pagePadding = 16;

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamilyFallback: const [
        'SF Pro Display',
        'PingFang SC',
        'Microsoft YaHei',
        'Roboto',
      ],
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: tertiaryColor,
        error: errorColor,
        brightness: Brightness.light,
      ),
    );

    final colorScheme = base.colorScheme.copyWith(
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE8F2FF),
      onPrimaryContainer: const Color(0xFF053A70),
      secondary: secondaryColor,
      tertiary: tertiaryColor,
      error: errorColor,
      surface: surfaceColor,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF9F9FB),
      surfaceContainer: surfaceContainerColor,
      surfaceContainerHigh: const Color(0xFFEDEEF2),
      surfaceContainerHighest: const Color(0xFFE3E5EA),
      onSurface: onSurfaceColor,
      onSurfaceVariant: const Color(0xFF6E7380),
      outline: const Color(0xFFB8BCC6),
      outlineVariant: const Color(0xFFE0E2E8),
    );

    final textTheme = base.textTheme
        .apply(bodyColor: onSurfaceColor, displayColor: onSurfaceColor)
        .copyWith(
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            height: 1.04,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            height: 1.12,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            height: 1.12,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            height: 1.18,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 1.2,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 1.2,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            height: 1.42,
            letterSpacing: 0,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 13,
            height: 1.35,
            letterSpacing: 0,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        );

    return base.copyWith(
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: surfaceColor,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor.withValues(alpha: 0.94),
        foregroundColor: onSurfaceColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 18),
        toolbarHeight: 56,
        iconTheme: const IconThemeData(color: onSurfaceColor, size: 23),
        actionsIconTheme: const IconThemeData(color: onSurfaceColor, size: 23),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLowest,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 16),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        indicatorColor: primaryColor.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? primaryColor : secondaryColor,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primaryColor : secondaryColor,
            size: selected ? 24 : 23,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _inputBorder(colorScheme.outlineVariant),
        enabledBorder: _inputBorder(Colors.transparent),
        focusedBorder: _inputBorder(primaryColor.withValues(alpha: 0.55)),
        errorBorder: _inputBorder(errorColor.withValues(alpha: 0.75)),
        focusedErrorBorder: _inputBorder(errorColor),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
        ),
        helperStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIconColor: colorScheme.onSurfaceVariant,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStateProperty.all(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return surfaceMutedColor;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return primaryColor;
            return colorScheme.onSurfaceVariant;
          }),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _filledButtonStyle(primaryColor),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _filledButtonStyle(primaryColor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        disabledColor: colorScheme.surfaceContainerHigh,
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w800,
        ),
        selectedColor: primaryColor.withValues(alpha: 0.13),
        checkmarkColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        modalBackgroundColor: surfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        dragHandleColor: colorScheme.outlineVariant.withValues(alpha: 0.72),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1D1D1F),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: const Color(0xFF9ED3FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    );
  }

  static Color semanticAmountColor(BuildContext context, bool isPositive) {
    return isPositive ? successColor : errorColor;
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static ButtonStyle _filledButtonStyle(Color color) {
    return FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFE0E2E8),
      disabledForegroundColor: const Color(0xFF8A8F99),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}
