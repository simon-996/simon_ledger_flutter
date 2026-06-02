import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/repositories/invite_repository.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/widgets/ledger_invite_widgets.dart';

void main() {
  final invite = LedgerInvite(
    code: 'ABCD1234',
    ledgerUuid: '00000000000000000000000012345678',
    ledgerName: '旅行账本',
    ledgerBaseCurrencyCode: 'USD',
    ledgerMemberCount: 2,
    ledgerMembers: [
      LedgerInviteMember(nickname: 'Simon', avatar: '😎', role: 'owner'),
      LedgerInviteMember(nickname: '小王', avatar: '🙂', role: 'editor'),
    ],
    role: 'editor',
    maxUses: 20,
    usedCount: 2,
    expiresAt: DateTime(2026, 6, 9),
    expired: false,
    disabled: false,
  );

  testWidgets('share dialog emphasizes code and exposes both copy actions', (
    tester,
  ) async {
    var copiedCode = false;
    var copiedText = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LedgerInviteShareDialog(
            invite: invite,
            onCopyCode: () async => copiedCode = true,
            onCopyText: () async => copiedText = true,
          ),
        ),
      ),
    );

    expect(find.text('ABCD1234'), findsOneWidget);
    expect(find.text('旅行账本'), findsOneWidget);
    expect(find.text('USD 美元'), findsOneWidget);
    expect(find.text('Simon'), findsOneWidget);

    await tester.tap(find.text('复制邀请码'));
    await tester.pump();
    expect(copiedCode, isTrue);

    await tester.tap(find.text('复制邀请文本'));
    await tester.pump();
    expect(copiedText, isTrue);
  });

  testWidgets('preview sheet joins only after explicit confirmation', (
    tester,
  ) async {
    var joinCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showModalBottomSheet<bool>(
                  context: context,
                  builder: (context) => LedgerInvitePreviewSheet(
                    invite: invite,
                    onJoin: () async => joinCalls += 1,
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(joinCalls, 0);
    expect(find.text('确认加入共享账本'), findsOneWidget);

    await tester.tap(find.text('确认加入'));
    await tester.pumpAndSettle();
    expect(joinCalls, 1);
    expect(find.text('确认加入共享账本'), findsNothing);
  });
}
