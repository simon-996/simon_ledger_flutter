import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/onboarding/presentation/widgets/onboarding_flow.dart';

void main() {
  testWidgets('onboarding flow advances and returns create ledger action', (
    tester,
  ) async {
    OnboardingAction? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showOnboardingFlow(context);
                },
                child: const Text('打开引导'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开引导'));
    await tester.pumpAndSettle();

    expect(find.text('建立你的第一本账'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('把每笔流水记清楚'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('需要共享时再同步'), findsOneWidget);

    await tester.tap(find.text('创建账本'));
    await tester.pumpAndSettle();

    expect(result, OnboardingAction.createLedger);
  });
}
