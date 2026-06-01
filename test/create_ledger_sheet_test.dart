import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/widgets/create_ledger_sheet.dart';

void main() {
  testWidgets('editing ledger shows newly added person immediately', (
    tester,
  ) async {
    final database = DatabaseService();
    final ledger = Ledger()
      ..uuid = 'local-ledger'
      ..name = '本地账本'
      ..baseCurrencyCode = 'CNY';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          authTokenProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(body: CreateLedgerSheet(existingLedger: ledger)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('新增人员'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final personNameField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '人员名称',
    );
    await tester.enterText(personNameField, '新成员');
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('新成员'), findsOneWidget);
  });
}
