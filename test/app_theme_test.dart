import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';

void main() {
  test('AppTheme uses the Apple calm visual baseline', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;

    expect(AppTheme.primaryColor, const Color(0xFF0B6F65));
    expect(AppTheme.surfaceColor, const Color(0xFFF5F5F7));
    expect(AppTheme.radiusLarge, 24);
    expect(theme.scaffoldBackgroundColor, AppTheme.surfaceColor);
    expect(scheme.surfaceContainerLowest, Colors.white);
    expect(scheme.surfaceContainerLow, const Color(0xFFF9F9FB));
    expect(scheme.outlineVariant, const Color(0xFFE2E3E8));
    expect(theme.cardTheme.elevation, 0);
    expect(theme.navigationBarTheme.height, 76);
    expect(
      theme.navigationBarTheme.backgroundColor,
      Colors.white.withValues(alpha: 0.86),
    );
  });

  test('AppTheme keeps option controls tonal without visible borders', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;
    final chipTheme = theme.chipTheme;
    final segmentStyle = theme.segmentedButtonTheme.style!;
    final outlinedStyle = theme.outlinedButtonTheme.style!;

    expect(chipTheme.side, BorderSide.none);
    expect(chipTheme.backgroundColor, scheme.surfaceContainerHigh);
    expect(
      chipTheme.selectedColor,
      AppTheme.primaryColor.withValues(alpha: 0.13),
    );
    expect(segmentStyle.side!.resolve(<WidgetState>{}), BorderSide.none);
    expect(
      segmentStyle.backgroundColor!.resolve(<WidgetState>{}),
      scheme.surfaceContainerHigh.withValues(alpha: 0.72),
    );
    expect(
      segmentStyle.backgroundColor!.resolve(<WidgetState>{
        WidgetState.selected,
      }),
      AppTheme.primaryColor.withValues(alpha: 0.13),
    );
    expect(outlinedStyle.side!.resolve(<WidgetState>{}), BorderSide.none);
    expect(
      outlinedStyle.backgroundColor!.resolve(<WidgetState>{}),
      scheme.surfaceContainerHigh.withValues(alpha: 0.62),
    );
  });

  test('AppTheme uses calm floating surfaces for modals', () {
    final theme = AppTheme.lightTheme;
    final scheme = theme.colorScheme;

    expect(
      theme.bottomSheetTheme.backgroundColor,
      scheme.surfaceContainerLowest,
    );
    expect(
      theme.bottomSheetTheme.modalBackgroundColor,
      scheme.surfaceContainerLowest,
    );
    expect(
      theme.bottomSheetTheme.dragHandleColor,
      scheme.outlineVariant.withValues(alpha: 0.72),
    );
    final bottomSheetShape =
        theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
    final bottomSheetRadius = bottomSheetShape.borderRadius as BorderRadius;
    expect(bottomSheetRadius.topLeft.x, 32);
    expect(bottomSheetRadius.topRight.x, 32);

    expect(theme.dialogTheme.backgroundColor, scheme.surfaceContainerLowest);
    final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
    final dialogRadius = dialogShape.borderRadius as BorderRadius;
    expect(dialogRadius.topLeft.x, 28);
    expect(dialogRadius.bottomRight.x, 28);
  });
}
