import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/preferences/onboarding_preference.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/home/presentation/screens/home_page.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/providers/ledger_stats_provider.dart';

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, required super.child});
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintProbeRender(onPaint);
}

class _PaintProbeRender extends RenderProxyBox {
  _PaintProbeRender(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

class _CountingLedgerStats extends LedgerStats {
  _CountingLedgerStats(this.onBuild);
  final VoidCallback onBuild;

  @override
  Future<Map<String, Map<String, double>>> build() async {
    onBuild();
    return {};
  }
}

void main() {
  testWidgets(
    'scrolling reuses static card paint but changed content repaints',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final paints = List<int>.filled(5, 0);
      var amount = 400;
      late StateSetter updateAmount;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  for (var index = 0; index < 5; index++)
                    StatefulBuilder(
                      builder: (context, setState) {
                        if (index == 0) updateAmount = setState;
                        return AppSectionCard(
                          child: _PaintProbe(
                            onPaint: () => paints[index]++,
                            child: SizedBox(
                              height: 240,
                              child: Text(
                                index == 0 ? '金额 $amount' : '卡片 $index',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      paints.fillRange(0, paints.length, 0);
      for (var frame = 1; frame <= 12; frame++) {
        controller.jumpTo(frame * 12);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(paints, everyElement(0));

      updateAmount(() => amount = 500);
      await tester.pump();
      expect(find.text('金额 500'), findsOneWidget);
      expect(paints.first, greaterThan(0));
      expect(paints.skip(1), everyElement(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tabs mount on first visit and keep input and scroll position', (
    tester,
  ) async {
    final mounts = List<int>.filled(3, 0);
    final tabs = [
      for (var index = 0; index < 3; index++)
        Builder(
          builder: (context) {
            mounts[index]++;
            return SingleChildScrollView(
              key: PageStorageKey('tab-$index'),
              child: Column(
                children: [
                  TextField(key: ValueKey('input-$index')),
                  const SizedBox(height: 2000),
                ],
              ),
            );
          },
        ),
    ];
    var currentIndex = 0;
    late StateSetter selectTab;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              selectTab = setState;
              return AppAnimatedIndexedStack(
                index: currentIndex,
                children: tabs,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mounts, [1, 0, 0]);
    await tester.enterText(find.byKey(const ValueKey('input-0')), '400');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final verticalScrollables = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    final scrollOffset = tester
        .state<ScrollableState>(verticalScrollables)
        .position
        .pixels;
    expect(scrollOffset, greaterThan(0));

    selectTab(() => currentIndex = 1);
    await tester.pumpAndSettle();
    expect(mounts, [1, 1, 0]);
    selectTab(() => currentIndex = 0);
    await tester.pumpAndSettle();
    expect(mounts, [1, 1, 0]);
    expect(find.text('400'), findsOneWidget);
    final firstTabScroll = find.descendant(
      of: find.byKey(const PageStorageKey('tab-0')),
      matching: verticalScrollables,
    );
    expect(
      tester.state<ScrollableState>(firstTabScroll).position.pixels,
      scrollOffset,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bookkeeping defers all-ledger statistics until the ledger tab opens',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        OnboardingPreference.completedKey: true,
      });
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'mobile-cost-ledger'
          ..name = '旅行账本'
          ..baseCurrencyCode = 'CNY',
      );
      var statsBuilds = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
            ledgerStatsProvider.overrideWith(
              () => _CountingLedgerStats(() => statsBuilds++),
            ),
          ],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(statsBuilds, 0);
      expect(
        find.byKey(const ValueKey('bookkeeping-amount-input')),
        findsOneWidget,
      );
      await tester.tap(find.text('账本').last);
      await tester.pumpAndSettle();
      expect(statsBuilds, 1);
      expect(find.text('旅行账本'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
