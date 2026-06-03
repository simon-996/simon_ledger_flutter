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
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showLedgerInviteShareSheet(
                  context: context,
                  ledgerUuid: invite.ledgerUuid,
                  initialInvite: invite,
                ),
                child: const Text('分享'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerInviteShareSheet), findsOneWidget);
    expect(
      tester.getSize(find.byType(LedgerInviteShareSheet)).height,
      lessThan(360),
    );
    expect(find.text('ABCD1234'), findsOneWidget);
    expect(find.text('旅行账本'), findsOneWidget);
    expect(find.text('USD 美元'), findsNothing);
    expect(find.text('Simon'), findsNothing);
    expect(find.textContaining('剩余'), findsOneWidget);
    expect(find.text('复制邀请码'), findsOneWidget);
    expect(find.text('复制邀请链接'), findsOneWidget);
    expect(find.text('复制全部信息'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    expect(find.text('生成邀请码'), findsNothing);
  });

  testWidgets(
    'share sheet copy buttons keep labels on one line on narrow screens',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showLedgerInviteShareSheet(
                    context: context,
                    ledgerUuid: invite.ledgerUuid,
                    initialInvite: invite,
                  ),
                  child: const Text('分享'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();

      expect(find.text('复制邀请码'), findsOneWidget);
      expect(find.text('复制全部信息'), findsOneWidget);
      expect(tester.getSize(find.text('复制全部信息')).height, lessThan(24));
    },
  );

  testWidgets('share sheet configures and regenerates invitation', (
    tester,
  ) async {
    int? submittedDays;
    int? submittedMaxUses;
    final newInvite = LedgerInvite(
      code: 'WXYZ9876',
      ledgerUuid: invite.ledgerUuid,
      ledgerName: invite.ledgerName,
      ledgerBaseCurrencyCode: invite.ledgerBaseCurrencyCode,
      ledgerMemberCount: invite.ledgerMemberCount,
      ledgerMembers: invite.ledgerMembers,
      role: invite.role,
      maxUses: 5,
      usedCount: 0,
      expiresAt: DateTime(2026, 6, 4),
      expired: false,
      disabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LedgerInviteShareSheet(
              ledgerUuid: invite.ledgerUuid,
              onRegenerate: (days, maxUses) async {
                submittedDays = days;
                submittedMaxUses = maxUses;
                return newInvite;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, '生成邀请码'), findsOneWidget);
    expect(find.text('1 天'), findsOneWidget);
    expect(find.text('5 次'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '生成邀请码'));
    await tester.pumpAndSettle();

    expect(submittedDays, 1);
    expect(submittedMaxUses, 5);
    expect(find.text('WXYZ9876'), findsOneWidget);
    expect(find.text('生成邀请码'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
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
