import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/features/home/presentation/screens/home_page.dart';

void main() {
  testWidgets('ledger statistics and account tabs do not show top titles', (
    tester,
  ) async {
    for (final index in [1, 2, 3]) {
      SharedPreferences.setMockInitialValues({});
      final database = DatabaseService();
      await database.saveLedger(
        Ledger()
          ..uuid = 'ledger-$index'
          ..name = '旅行账本'
          ..baseCurrencyCode = 'CNY',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(home: HomePage(initialIndex: index)),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
    }
  });
}
