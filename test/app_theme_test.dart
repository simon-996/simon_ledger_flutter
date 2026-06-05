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
}
