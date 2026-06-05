import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';

void main() {
  testWidgets('AppSectionCard uses the Apple Calm floating surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppSectionCard(child: Text('内容'))),
      ),
    );

    final context = tester.element(find.byType(AppSectionCard));
    final colorScheme = Theme.of(context).colorScheme;
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(AppSectionCard),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    final borderRadius = decoration.borderRadius! as BorderRadius;
    final border = decoration.border! as Border;

    expect(decoration.color, colorScheme.surfaceContainerLowest);
    expect(borderRadius.topLeft.x, AppTheme.radiusLarge);
    expect(
      border.top.color,
      colorScheme.outlineVariant.withValues(alpha: 0.68),
    );
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('AppLoadingState uses a compact Apple status panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppLoadingState(title: '正在加载', message: '请稍候'),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(AppLoadingState),
        matching: find.byType(AppSectionCard),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .strokeWidth,
      2.4,
    );
  });
}
