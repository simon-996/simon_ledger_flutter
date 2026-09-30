import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

export 'app_colors.dart';

class AppTheme {
  static const double navigationBreakpoint = 720;
  static const double contentMaxWidth = 1240;
  static const FontWeight headingWeight = FontWeight.w600;
  static const FontWeight emphasisWeight = FontWeight.w700;

  static const double radiusSmall = 12;
  static const double radiusMedium = 18;
  static const double radiusLarge = 24;
  static const double radiusXLarge = 30;
  static const double pagePadding = 16;
  static const double modalBarrierOpacity = 0.38;

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
        seedColor: AppPalette.primary,
        primary: AppPalette.primary,
        secondary: AppPalette.secondary,
        tertiary: AppPalette.warning,
        error: AppPalette.error,
        brightness: Brightness.light,
      ),
    );

    final colorScheme = base.colorScheme.copyWith(
      primary: AppPalette.primary,
      onPrimary: AppPalette.onPrimary,
      primaryContainer: AppPalette.primaryContainer,
      onPrimaryContainer: AppPalette.onPrimaryContainer,
      secondary: AppPalette.secondary,
      onSecondary: AppPalette.onPrimary,
      secondaryContainer: AppPalette.surfaceMuted,
      onSecondaryContainer: AppPalette.content,
      tertiary: AppPalette.warning,
      onTertiary: AppPalette.onPrimary,
      tertiaryContainer: AppPalette.warningContainer,
      onTertiaryContainer: AppPalette.onWarningContainer,
      error: AppPalette.error,
      onError: AppPalette.onPrimary,
      errorContainer: AppPalette.errorContainer,
      onErrorContainer: AppPalette.onErrorContainer,
      inverseSurface: AppPalette.content,
      onInverseSurface: AppPalette.surface,
      inversePrimary: AppPalette.inversePrimary,
      scrim: AppPalette.content,
      surface: AppPalette.background,
      surfaceContainerLowest: AppPalette.surface,
      surfaceContainerLow: AppPalette.surfaceLow,
      surfaceContainer: AppPalette.surface,
      surfaceContainerHigh: AppPalette.surfaceMuted,
      surfaceContainerHighest: AppPalette.surfaceStrong,
      onSurface: AppPalette.content,
      onSurfaceVariant: AppPalette.secondary,
      outline: AppPalette.outline,
      outlineVariant: AppPalette.divider,
    );

    final textTheme = base.textTheme
        .apply(bodyColor: AppPalette.content, displayColor: AppPalette.content)
        .copyWith(
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 48,
            fontWeight: headingWeight,
            letterSpacing: 0,
            height: 1.04,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 30,
            fontWeight: headingWeight,
            letterSpacing: 0,
            height: 1.12,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 24,
            fontWeight: headingWeight,
            letterSpacing: 0,
            height: 1.12,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 21,
            fontWeight: headingWeight,
            letterSpacing: 0,
            height: 1.18,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 17,
            fontWeight: headingWeight,
            letterSpacing: 0,
            height: 1.2,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 15,
            fontWeight: headingWeight,
            letterSpacing: 0,
            height: 1.2,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 15,
            height: 1.42,
            letterSpacing: 0,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 13,
            height: 1.35,
            letterSpacing: 0,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 15,
            fontWeight: headingWeight,
            letterSpacing: 0,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 13,
            fontWeight: headingWeight,
            letterSpacing: 0,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 12,
            fontWeight: headingWeight,
            letterSpacing: 0,
          ),
        );

    return base.copyWith(
      colorScheme: colorScheme,
      extensions: const [AppColors.light],
      textTheme: textTheme,
      scaffoldBackgroundColor: AppPalette.background,
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
        backgroundColor: AppPalette.background.withValues(alpha: 0.94),
        foregroundColor: AppPalette.content,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 18),
        toolbarHeight: 56,
        iconTheme: const IconThemeData(color: AppPalette.content, size: 23),
        actionsIconTheme: const IconThemeData(
          color: AppPalette.content,
          size: 23,
        ),
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
        backgroundColor: AppPalette.surface.withValues(alpha: 0.96),
        indicatorColor: AppPalette.primary.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? AppPalette.primary : AppPalette.secondary,
            fontWeight: selected ? emphasisWeight : FontWeight.w500,
            fontSize: 12,
            letterSpacing: 0,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppPalette.primary : AppPalette.secondary,
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
        focusedBorder: _inputBorder(AppPalette.primary.withValues(alpha: 0.55)),
        errorBorder: _inputBorder(AppPalette.error.withValues(alpha: 0.75)),
        focusedErrorBorder: _inputBorder(AppPalette.error),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        helperStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIconColor: colorScheme.onSurfaceVariant,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStateProperty.all(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppPalette.surface;
            }
            return AppPalette.surfaceMuted;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppPalette.primary;
            }
            return colorScheme.onSurfaceVariant;
          }),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: emphasisWeight, letterSpacing: 0),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _filledButtonStyle(AppPalette.primary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _filledButtonStyle(AppPalette.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.primary,
          side: BorderSide(color: AppPalette.primary.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: emphasisWeight,
            letterSpacing: 0,
          ),
        ).copyWith(overlayColor: _tintedButtonOverlayColor(AppPalette.primary)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.primary,
          textStyle: const TextStyle(
            fontWeight: emphasisWeight,
            letterSpacing: 0,
          ),
        ).copyWith(overlayColor: _tintedButtonOverlayColor(AppPalette.primary)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: _tintedButtonOverlayColor(AppPalette.primary),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppPalette.primary,
        foregroundColor: AppPalette.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppPalette.surface,
        disabledColor: colorScheme.surfaceContainerHigh,
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppPalette.primary,
          fontWeight: emphasisWeight,
        ),
        selectedColor: AppPalette.primary.withValues(alpha: 0.13),
        checkmarkColor: AppPalette.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        modalBarrierColor: colorScheme.scrim.withValues(
          alpha: modalBarrierOpacity,
        ),
        backgroundColor: AppPalette.background,
        modalBackgroundColor: AppPalette.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        dragHandleColor: colorScheme.outlineVariant.withValues(alpha: 0.72),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        barrierColor: colorScheme.scrim.withValues(alpha: modalBarrierOpacity),
        backgroundColor: AppPalette.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.content,
        contentTextStyle: const TextStyle(color: AppPalette.onPrimary),
        actionTextColor: AppPalette.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static WidgetStateProperty<Color?> _filledButtonOverlayColor() {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return null;
      if (states.contains(WidgetState.pressed)) {
        return AppPalette.content.withValues(alpha: 0.1);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return AppPalette.onPrimary.withValues(alpha: 0.1);
      }
      return null;
    });
  }

  static WidgetStateProperty<Color?> _tintedButtonOverlayColor(Color color) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return null;
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return color.withValues(alpha: 0.08);
      }
      return null;
    });
  }

  static ButtonStyle _filledButtonStyle(Color color) {
    return FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: AppPalette.onPrimary,
      disabledBackgroundColor: AppPalette.divider,
      disabledForegroundColor: AppPalette.disabledContent,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: emphasisWeight,
        letterSpacing: 0,
      ),
    ).copyWith(overlayColor: _filledButtonOverlayColor());
  }
}
