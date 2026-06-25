import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';

void main() {
  test('AppTheme uses a calm semantic color baseline', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;

    expect(AppTheme.primaryColor, const Color(0xFF3F78A3));
    expect(AppTheme.incomeColor, const Color(0xFF3F7F63));
    expect(AppTheme.expenseColor, const Color(0xFF9F6258));
    expect(AppTheme.surfaceColor, const Color(0xFFF5F5F7));
    expect(AppTheme.radiusLarge, 24);
    expect(theme.scaffoldBackgroundColor, AppTheme.surfaceColor);
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
    expect(
      chipTheme.selectedColor,
      AppTheme.primaryColor.withValues(alpha: 0.13),
    );
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
      BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
    );
    expect(outlinedStyle.backgroundColor, isNull);
  });

  test('AppTheme gives standard buttons visible pressed state layers', () {
    final theme = AppTheme.lightTheme;
    const pressed = <WidgetState>{WidgetState.pressed};

    expect(
      theme.filledButtonTheme.style!.overlayColor!.resolve(pressed),
      AppTheme.onSurfaceColor.withValues(alpha: 0.1),
    );
    expect(
      theme.outlinedButtonTheme.style!.overlayColor!.resolve(pressed),
      AppTheme.primaryColor.withValues(alpha: 0.14),
    );
    expect(
      theme.textButtonTheme.style!.overlayColor!.resolve(pressed),
      AppTheme.primaryColor.withValues(alpha: 0.14),
    );
    expect(
      theme.iconButtonTheme.style!.overlayColor!.resolve(pressed),
      AppTheme.primaryColor.withValues(alpha: 0.14),
    );
  });

  test('AppTheme uses calm floating surfaces for modals', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;

    expect(theme.bottomSheetTheme.backgroundColor, AppTheme.surfaceColor);
    expect(theme.bottomSheetTheme.modalBackgroundColor, AppTheme.surfaceColor);
    expect(
      theme.bottomSheetTheme.dragHandleColor,
      scheme.outlineVariant.withValues(alpha: 0.72),
    );
    final bottomSheetShape =
        theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
    final bottomSheetRadius = bottomSheetShape.borderRadius as BorderRadius;
    expect(bottomSheetRadius.topLeft.x, 32);
    expect(bottomSheetRadius.topRight.x, 32);

    expect(theme.dialogTheme.backgroundColor, AppTheme.surfaceColor);
    final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
    final dialogRadius = dialogShape.borderRadius as BorderRadius;
    expect(dialogRadius.topLeft.x, 28);
    expect(dialogRadius.bottomRight.x, 28);
  });
}
