import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';

void main() {
  testWidgets('dragging a transaction restores its scale without opening it', (
    tester,
  ) async {
    var taps = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              AppTransactionTile(
                category: '住宿',
                date: '昨天',
                people: '张三',
                amount: '- ¥400.00',
                isExpense: true,
                onTap: () => taps++,
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('住宿')),
    );
    await tester.pump(AppMotion.micro);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );

    await gesture.moveBy(const Offset(0, -80));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(AppMotion.micro);
    expect(controller.offset, greaterThan(0));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('moving back after a drag does not reactivate press feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppPressable(
              child: SizedBox(
                width: 200,
                height: 200,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppPressable)),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(AppMotion.micro);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
  });

  for (final slivers in [false, true]) {
    testWidgets(
      'new entries appear immediately during ${slivers ? 'sliver' : 'list'} scrolling',
      (tester) async {
        Widget itemBuilder(BuildContext context, int index) => AppAnimatedEntry(
          key: ValueKey('entry-$index'),
          delay: const Duration(milliseconds: 270),
          child: SizedBox(height: 100, child: Text('流水 $index')),
        );
        final scrollView = slivers
            ? CustomScrollView(
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                slivers: [
                  SliverList.builder(itemCount: 40, itemBuilder: itemBuilder),
                ],
              )
            : ListView.builder(
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                itemCount: 40,
                itemBuilder: itemBuilder,
              );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(height: 300, width: 360, child: scrollView),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Scrollable)),
        );
        await gesture.moveBy(const Offset(0, -600));
        await tester.pump();
        final newEntry = find.byKey(const ValueKey('entry-6'));
        expect(newEntry, findsOneWidget);
        final opacity = tester.widget<FadeTransition>(
          find.descendant(of: newEntry, matching: find.byType(FadeTransition)),
        );
        expect(opacity.opacity.value, 1);
        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('scrolling ends pending entrance animations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                AppAnimatedEntry(
                  delay: Duration(milliseconds: 270),
                  child: SizedBox(height: 300, child: Text('记账内容')),
                ),
                SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final entrance = find.descendant(
      of: find.byType(AppAnimatedEntry),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(entrance).opacity.value, 0);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Scrollable)),
    );
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(tester.widget<FadeTransition>(entrance).opacity.value, 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('vertical scrolling ends entrance inside a horizontal list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const [
                      AppAnimatedEntry(
                        delay: Duration(milliseconds: 270),
                        child: SizedBox(width: 150, child: Text('人员结余')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('人员结余')),
    );
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    final entrance = find.descendant(
      of: find.byType(AppAnimatedEntry),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(entrance).opacity.value, 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('initial entrance still animates when the page is stationary', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppAnimatedEntry(child: Text('内容')),
          ),
        ),
      ),
    );
    final entrance = find.descendant(
      of: find.byType(AppAnimatedEntry),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(entrance).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 80));
    final progress = tester.widget<FadeTransition>(entrance).opacity.value;
    expect(progress, greaterThan(0));
    expect(progress, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(entrance).opacity.value, 1);
  });
}
