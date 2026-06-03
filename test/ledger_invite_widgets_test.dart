import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
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
      const LedgerInviteMember(nickname: 'Simon', avatar: '😎', role: 'owner'),
      const LedgerInviteMember(nickname: '小王', avatar: '🙂', role: 'editor'),
    ],
    role: 'editor',
    maxUses: 20,
    usedCount: 2,
    expiresAt: DateTime(2026, 6, 9),
    expired: false,
    disabled: false,
  );

  testWidgets('share sheet keeps sender flow lightweight', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () =>
                  showLedgerInviteShareSheet(context: context, invite: invite),
              child: const Text('分享'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerInviteShareSheet), findsOneWidget);
    expect(find.text('ABCD1234'), findsOneWidget);
    expect(find.text('旅行账本'), findsOneWidget);
    expect(find.text('USD 美元'), findsNothing);
    expect(find.text('Simon'), findsNothing);
    expect(find.text('复制邀请码'), findsOneWidget);
    expect(find.text('复制邀请链接'), findsOneWidget);
    expect(find.text('复制完整邀请'), findsOneWidget);
  });

  testWidgets('join page joins only after explicit confirmation', (
    tester,
  ) async {
    var joinCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authTokenProvider.overrideWith(
            (ref) async => const AuthToken(name: 'satoken', value: 'token'),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (context) => LedgerInviteJoinPage(
                        code: invite.code,
                        initialInvite: invite,
                        onJoin: () async => joinCalls += 1,
                      ),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
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
    await tester.pump(const Duration(seconds: 2));
  });
}
