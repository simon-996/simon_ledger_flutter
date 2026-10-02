import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_draft_review.dart';

final ledger = Ledger()
  ..uuid = 'local-ledger'
  ..name = '旅行'
  ..baseCurrencyCode = 'THB'
  ..exchangeRateToCNY = 0.2
  ..personUuids = ['local-person'];
final person = Person()
  ..uuid = 'local-person'
  ..syncedRemoteUuid = 'remote-person'
  ..name = '陈鑫';

Future<void> showReview(
  WidgetTester tester,
  AiDraft draft, {
  Future<void> Function(AiDraft)? onConfirm,
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: AiDraftReview(
          draft: draft,
          ledger: ledger,
          people: [person],
          position: 1,
          total: 1,
          busy: false,
          onConfirm: onConfirm ?? (_) async {},
          onSkip: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AiDraft draft({
  List<String> people = const [],
  String? payer,
  AiPaymentMode? paymentMode,
  List<AiPersonMatch> matches = const [],
  List<String> unresolved = const [],
}) => AiDraft(
  sourceText: '陈欣买了两杯饮料三十元',
  type: 0,
  amount: 30,
  currencyCode: 'CNY',
  categorySuggestion: '餐饮',
  personUuids: people,
  payerPersonUuid: payer,
  paymentMode: paymentMode,
  personMatches: matches,
  unresolvedNames: unresolved,
);

void main() {
  testWidgets('pending participant suppresses a definitive split preview', (
    tester,
  ) async {
    await showReview(
      tester,
      draft(
        people: ['local-person'],
        paymentMode: AiPaymentMode.sharedWallet,
        matches: const [AiPersonMatch(sourceName: '小李', role: 'participant')],
      ),
    );
    expect(find.textContaining('人均分'), findsNothing);
    expect(find.textContaining('每人 CNY'), findsNothing);
    expect(find.text('人员待确认，确认后显示分摊金额'), findsOneWidget);
  });

  testWidgets(
    'legacy unresolved payer requires role before choosing identity',
    (tester) async {
      await showReview(tester, draft(unresolved: ['陈欣']));
      expect(find.text('选择人员身份'), findsOneWidget);
      var choice = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      choice.onChanged!('payer');
      await tester.pumpAndSettle();
      choice = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      choice.onChanged!('local-person');
      await tester.pumpAndSettle();
      final grids = tester.widgetList<AppPersonChoiceGrid>(
        find.byType(AppPersonChoiceGrid),
      );
      expect(grids.first.selectedIds, isEmpty);
      expect(grids.last.selectedId, 'local-person');
    },
  );

  testWidgets('missing identities explain that the person left the ledger', (
    tester,
  ) async {
    await showReview(
      tester,
      draft(
        people: ['missing-person'],
        payer: 'missing-person',
        matches: const [
          AiPersonMatch(
            sourceName: '老陈',
            role: 'payer',
            personUuid: 'missing-person',
          ),
        ],
      ),
    );
    expect(find.text('这位人员当前不在账本中，请重新选择'), findsWidgets);
    expect(find.textContaining('老陈'), findsWidgets);
    expect(find.textContaining('已失效'), findsNothing);
  });

  testWidgets(
    'resolving a payer does not silently add that person as a participant',
    (tester) async {
      await showReview(
        tester,
        draft(
          matches: const [
            AiPersonMatch(
              sourceName: '陈欣',
              role: 'participant',
              candidatePersonUuids: ['remote-person'],
            ),
            AiPersonMatch(
              sourceName: '陈欣',
              role: 'payer',
              candidatePersonUuids: ['remote-person'],
            ),
          ],
        ),
      );
      final choices = tester.widgetList<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      choices.last.onChanged!('local-person');
      await tester.pumpAndSettle();
      final grids = tester.widgetList<AppPersonChoiceGrid>(
        find.byType(AppPersonChoiceGrid),
      );
      expect(grids.first.selectedIds, isEmpty);
      expect(grids.last.selectedId, 'local-person');
      expect(find.text('请选择承担人'), findsOneWidget);
      expect(find.textContaining('“陈欣”的承担人尚未确认'), findsOneWidget);
    },
  );

  testWidgets('remote participant and payer resolve to local ledger people', (
    tester,
  ) async {
    await showReview(
      tester,
      draft(people: ['remote-person'], payer: 'remote-person'),
    );
    final grids = tester.widgetList<AppPersonChoiceGrid>(
      find.byType(AppPersonChoiceGrid),
    );
    expect(grids.first.selectedIds, contains('local-person'));
    expect(find.textContaining('原参与人已失效'), findsNothing);
    expect(find.textContaining('原付款人已失效'), findsNothing);
  });

  testWidgets(
    'unfinished review shows decisions instead of fabricated split values',
    (tester) async {
      await showReview(tester, draft());
      expect(find.text('请选择承担人'), findsOneWidget);
      expect(find.text('付款方式待确认'), findsWidgets);
      expect(find.textContaining('0 人承担'), findsNothing);
      expect(find.textContaining('每人 CNY —'), findsNothing);
      expect(find.textContaining('共同钱包付款'), findsNothing);
    },
  );

  testWidgets(
    'legacy missing payer must be explicitly confirmed before saving',
    (tester) async {
      AiDraft? saved;
      await showReview(
        tester,
        draft(people: ['local-person']),
        onConfirm: (value) async => saved = value,
      );
      await tester.tap(find.text('确认记账'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.ensureVisible(find.text('共同钱包'));
      await tester.tap(find.text('共同钱包'));
      await tester.tap(find.text('确认记账'));
      await tester.pumpAndSettle();
      expect(saved?.effectivePaymentMode, AiPaymentMode.sharedWallet);
    },
  );

  testWidgets(
    'approximate name shows original expression and actual matched name',
    (tester) async {
      await showReview(
        tester,
        draft(
          people: ['remote-person'],
          payer: 'remote-person',
          matches: const [
            AiPersonMatch(
              sourceName: '陈欣',
              role: 'participant',
              personUuid: 'remote-person',
              matchedName: '陈鑫',
              approximate: true,
              candidatePersonUuids: ['remote-person'],
            ),
          ],
        ),
      );
      expect(find.textContaining('“陈欣”'), findsWidgets);
      expect(find.textContaining('近似匹配'), findsWidgets);
      expect(find.textContaining('陈鑫'), findsWidgets);
    },
  );

  for (final width in [280.0, 900.0]) {
    testWidgets('compact amount keeps conversion secondary at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showReview(
        tester,
        draft(
          people: ['local-person'],
          paymentMode: AiPaymentMode.sharedWallet,
        ),
      );
      expect(find.text('按账本汇率约合 THB 150.00'), findsOneWidget);
      expect(find.text('每人 CNY 30.00'), findsOneWidget);
      expect(find.text('每人 ≈ THB 150.00'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ambiguous names remain readable on phone with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await showReview(
      tester,
      draft(
        matches: const [
          AiPersonMatch(
            sourceName: '陈欣或者小陈',
            role: 'participant',
            candidatePersonUuids: ['remote-person'],
          ),
          AiPersonMatch(sourceName: '另外一位朋友', role: 'payer'),
        ],
      ),
      textScale: 1.5,
    );
    await tester.ensureVisible(find.text('忽略本次识别').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('陈欣或者小陈'), findsOneWidget);
    expect(find.textContaining('另外一位朋友'), findsOneWidget);
    expect(find.text('付款方式待确认'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
