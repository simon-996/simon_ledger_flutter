import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/widgets/share_ledger_image_widget.dart';

void main() {
  testWidgets('share ledger image renders without bottom overflow', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-share-image'
      ..name = '端午旅行共享账本'
      ..baseCurrencyCode = 'USD'
      ..exchangeRateToCNY = 7.2
      ..personUuids = List.generate(8, (index) => 'person-$index');

    final people = List.generate(8, (index) {
      return Person()
        ..uuid = 'person-$index'
        ..name = '成员${index + 1}'
        ..avatar = index.isEven ? '🙂' : '😎';
    });

    final transactions = List.generate(18, (index) {
      return TransactionRecord()
        ..uuid = 'transaction-$index'
        ..ledgerUuid = ledger.uuid
        ..type = index.isEven ? 0 : 1
        ..amount = 123456.78 + index
        ..currencyCode = index.isEven ? 'USD' : 'CNY'
        ..category = index.isEven ? '餐饮' : '红包'
        ..note = index % 3 == 0
            ? '这是一条比较长的备注，用来验证导出图片在底部和右侧都不会出现 overflow 提示。'
            : ''
        ..personUuids = ['person-${index % people.length}']
        ..createdAt = DateTime(2026, 6, 4, 10, index);
    });

    await tester.binding.setSurfaceSize(const Size(420, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: ShareLedgerImageWidget(
                ledger: ledger,
                transactions: transactions,
                summaryTransactions: transactions,
                peoplePool: people,
                pageIndex: 2,
                totalPages: 3,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Simon Ledger'), findsOneWidget);
  });
}
