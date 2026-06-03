import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/features/statistics/presentation/widgets/statistics_tab.dart';

void main() {
  testWidgets(
    'statistics filters stay complete before a ledger preference loads',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = DatabaseService();
      final ledger = Ledger()
        ..uuid = 'stats-ledger'
        ..name = '旅行账本'
        ..baseCurrencyCode = 'CNY';
      await database.saveLedger(ledger);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(body: StatisticsTab(ledgers: [ledger])),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('正在准备统计'), findsNothing);
      expect(find.text('旅行账本'), findsOneWidget);
      expect(find.text('收支类型'), findsOneWidget);
      expect(find.text('时间范围'), findsOneWidget);
      expect(find.text('近7天'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('本年'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      final timeFilterTop = tester.getTopLeft(find.text('近7天')).dy;
      expect(
        tester.getTopLeft(find.text('本月')).dy,
        moreOrLessEquals(timeFilterTop),
      );
      expect(
        tester.getTopLeft(find.text('本年')).dy,
        moreOrLessEquals(timeFilterTop),
      );
      expect(
        tester.getTopLeft(find.text('全部')).dy,
        moreOrLessEquals(timeFilterTop),
      );
    },
  );
}
