import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/features/conflicts/presentation/widgets/conflict_entry_widgets.dart';

void main() {
  testWidgets('conflict notice stays hidden when there is nothing to confirm', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ConflictNoticeBanner(count: 0))),
    );

    expect(find.textContaining('数据需要确认'), findsNothing);
  });

  testWidgets('conflict notice shows count and opens item handling', (
    tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConflictNoticeBanner(count: 2, onTap: () => tapCount += 1),
        ),
      ),
    );

    expect(find.text('有 2 项数据需要确认'), findsOneWidget);
    expect(find.text('逐项处理'), findsOneWidget);

    await tester.tap(find.text('逐项处理'));
    expect(tapCount, 1);
  });

  testWidgets('ledger conflict chip is independent from sync status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              Text('已同步'),
              LedgerConflictChip(count: 3),
              LedgerConflictChip(count: 0),
            ],
          ),
        ),
      ),
    );

    expect(find.text('已同步'), findsOneWidget);
    expect(find.text('冲突 3 项'), findsOneWidget);
    expect(find.text('冲突 0 项'), findsNothing);
  });
}
