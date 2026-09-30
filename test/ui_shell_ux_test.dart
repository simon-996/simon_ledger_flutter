import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/preferences/onboarding_preference.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/home/presentation/screens/home_page.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, Size size) async {
    SharedPreferences.setMockInitialValues({
      OnboardingPreference.completedKey: true,
    });
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(DatabaseService()),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const HomePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'wide shell uses a rail and narrow shell keeps bottom navigation',
    (tester) async {
      await pumpHome(tester, const Size(1100, 844));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty bookkeeping creates a ledger and returns to recording', (
    tester,
  ) async {
    await pumpHome(tester, const Size(390, 844));
    await tester.tap(find.text('创建第一本账本'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '账本名称',
      ),
      '日常生活',
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '对人民币汇率',
      ),
      findsNothing,
    );
    expect(find.text('人民币账本汇率固定为 1'), findsOneWidget);
    await tester.tap(find.text('创建账本'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      findsOneWidget,
    );
    expect(find.text('日常生活'), findsWidgets);
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.selectedIndex, 0);
    expect(tester.takeException(), isNull);
  });
}
