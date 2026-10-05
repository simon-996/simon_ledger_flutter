import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/preferences/bookkeeping_preference.dart';
import 'package:simon_ledger_flutter/core/preferences/onboarding_preference.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/home/presentation/screens/home_page.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_draft_review.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/bookkeeping_tab.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/edit_transaction_sheet.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/transaction_form_components.dart';

const _captureDir = String.fromEnvironment('UX_CAPTURE_DIR');

void main() {
  setUpAll(() async {
    final windowsDir = Platform.environment['WINDIR'];
    final font = File(
      Platform.isMacOS
          ? '/System/Library/Fonts/STHeiti Light.ttc'
          : windowsDir == null
          ? ''
          : '$windowsDir/Fonts/msyh.ttc',
    );
    if (font.existsSync()) {
      final bytes = await font.readAsBytes();
      for (final family in ['Microsoft YaHei', 'Roboto', 'Ahem']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
    final runtimeDir = File(Platform.resolvedExecutable).parent;
    final runtimeRoot = runtimeDir.parent.parent;
    // Dart runs under dart-sdk/bin; widget tests run under engine/windows-x64.
    // Both use the same cache/artifacts material font asset.
    final iconCandidates = [
      File(
        '${runtimeRoot.path}/artifacts/material_fonts/materialicons-regular.otf',
      ),
      File('${runtimeRoot.path}/material_fonts/materialicons-regular.otf'),
    ];
    final icons = iconCandidates.firstWhere(
      (file) => file.existsSync(),
      orElse: () => iconCandidates.first,
    );
    if (icons.existsSync()) {
      final bytes = await icons.readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  setUp(
    () => SharedPreferences.setMockInitialValues({
      OnboardingPreference.completedKey: true,
    }),
  );
  testWidgets('saved notice stays above footer with real Chinese font', (
    tester,
  ) async {
    final data = await _fixture();
    final boundary = GlobalKey();
    await _mount(
      tester,
      data.database,
      boundary,
      Scaffold(body: BookkeepingTab(ledgers: [data.ledger])),
      width: 390,
    );
    await tester.enterText(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      '12.50',
    );
    await tester.tap(find.text('保存记账'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester.getBottomLeft(find.text('撤销')).dy,
      lessThan(tester.getTopLeft(find.text('保存记账')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => _capture(boundary, 'saved-notice-390'));
    AppNotice.dismiss();
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets('date and time panel fits real Chinese font at $width', (
      tester,
    ) async {
      final data = await _fixture();
      final boundary = GlobalKey();
      await _mount(
        tester,
        data.database,
        boundary,
        Scaffold(
          body: TransactionDateControl(
            date: DateTime(2026, 10, 4, 19, 42),
            onChanged: (_) {},
          ),
        ),
        width: width,
      );
      await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => _capture(boundary, 'date-time-${width.toInt()}'),
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-calendar-toggle')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => _capture(boundary, 'date-calendar-${width.toInt()}'),
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
  }
  testWidgets('date panel keeps completion above keyboard at large text size', (
    tester,
  ) async {
    final data = await _fixture();
    final boundary = GlobalKey();
    await _mount(
      tester,
      data.database,
      boundary,
      Scaffold(
        body: TransactionDateControl(
          date: DateTime(2026, 10, 4, 19, 42),
          onChanged: (_) {},
        ),
      ),
      width: 320,
      textScale: 1.5,
    );
    await tester.tap(find.byKey(const ValueKey('transaction-date-control')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(
      find.byKey(const ValueKey('transaction-hour-input')),
      '18',
    );
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('完成')).dy, lessThanOrEqualTo(544));
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => _capture(boundary, 'date-keyboard-large-text-320'),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
  testWidgets('multi currency totals fit bookkeeping with real Chinese fonts', (
    tester,
  ) async {
    final data = await _fixture();
    data.ledger.baseCurrencyCode = 'USD';
    data.ledger.exchangeRateToCNY = 7.2;
    await data.database.saveLedger(data.ledger);
    await BookkeepingDraftPreference.write(
      BookkeepingDraft(
        ledgerUuid: data.ledger.uuid,
        transactionType: 0,
        category: '餐饮',
        currencyCode: 'USD',
        personUuids: ['xiaowang', 'xiaoli'],
      ),
    );
    final boundary = GlobalKey();
    await _mount(tester, data.database, boundary, const HomePage(), width: 390);
    await tester.enterText(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      '100',
    );
    await tester.pumpAndSettle();
    final lastAmount = find.text('每人 ≈ CNY 360.00');
    await tester.ensureVisible(lastAmount);
    await tester.pumpAndSettle();
    expect(find.text('总额 USD 100.00'), findsOneWidget);
    expect(find.text('每人 USD 50.00'), findsOneWidget);
    expect(find.text('总额 ≈ CNY 720.00'), findsOneWidget);
    expect(lastAmount, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => _capture(boundary, 'bookkeeping-multi-currency-390'),
    );
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'populated bookkeeping with Chinese fonts fits ${width.toInt()}px shell',
      (tester) async {
        final data = await _fixture();
        await BookkeepingDraftPreference.write(
          BookkeepingDraft(
            ledgerUuid: data.ledger.uuid,
            transactionType: 0,
            category: '餐饮',
            currencyCode: 'CNY',
            personUuids: ['xiaowang', 'xiaoli'],
          ),
        );
        final boundary = GlobalKey();
        await _mount(
          tester,
          data.database,
          boundary,
          const HomePage(),
          width: width,
        );
        expect(find.byType(BookkeepingTab), findsOneWidget);
        expect(find.text('¥ CNY · 人民币'), findsOneWidget);
        expect(
          find.byType(NavigationRail),
          width > 720 ? findsOneWidget : findsNothing,
        );
        await tester.enterText(
          find.byKey(const ValueKey('bookkeeping-amount-input')),
          '68',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => _capture(boundary, 'bookkeeping-${width.toInt()}'),
        );
        if (width == 390) {
          await tester.ensureVisible(find.text('谁承担'));
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => _capture(boundary, 'bookkeeping-people-390'),
          );
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.enterText(
          find.byKey(const ValueKey('bookkeeping-amount-input')),
          '-5',
        );
        await tester.tap(find.text('保存记账'));
        await tester.pumpAndSettle();
        expect(find.text('请输入大于 0 的有效金额'), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('请输入大于 0 的有效金额'))
              .didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.getBottomLeft(find.byKey(const ValueKey('save-enabled'))).dy,
          lessThanOrEqualTo(544),
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => _capture(
            boundary,
            'bookkeeping-validation-keyboard-${width.toInt()}',
          ),
        );
      },
    );
  }
  testWidgets(
    'populated edit sheet fits Chinese fields and keyboard validation',
    (tester) async {
      final data = await _fixture();
      final boundary = GlobalKey();
      await _mount(
        tester,
        data.database,
        boundary,
        Scaffold(
          resizeToAvoidBottomInset: false,
          body: EditTransactionSheet(
            transaction: data.record,
            ledger: data.ledger,
          ),
        ),
        width: 390,
      );
      expect(find.text('¥ CNY · 人民币'), findsOneWidget);
      expect(find.text('保存修改'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => _capture(boundary, 'edit-390'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.enterText(find.byType(TextField).first, 'NaN');
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();
      expect(find.text('请输入大于 0 的有效金额'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('请输入大于 0 的有效金额'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        tester.getBottomLeft(find.text('保存修改')).dy,
        lessThanOrEqualTo(544),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => _capture(boundary, 'edit-validation-keyboard-390'),
      );
    },
  );
  testWidgets(
    'AI review keeps progress and confirmation visible with Chinese font',
    (tester) async {
      final data = await _fixture();
      final boundary = GlobalKey();
      await _mount(
        tester,
        data.database,
        boundary,
        Scaffold(
          body: AiDraftReview(
            draft: AiDraft(
              sourceText: '小王替大家付了六十八元晚餐，小王和小李平均分摊。',
              type: 0,
              amount: 68,
              currencyCode: 'CNY',
              categorySuggestion: '餐饮',
              personUuids: const ['xiaowang', 'xiaoli'],
              unresolvedNames: const [],
              payerPersonUuid: 'xiaowang',
              happenedAt: DateTime(2026, 9, 28, 18, 30),
              note: '晚餐',
            ),
            ledger: data.ledger,
            people: data.people,
            position: 2,
            total: 3,
            busy: false,
            onConfirm: (_) async {},
            onSkip: () {},
          ),
        ),
        width: 390,
      );
      expect(find.text('第 2/3 笔'), findsOneWidget);
      expect(find.text('¥ CNY · 人民币'), findsOneWidget);
      expect(find.text('确认记账'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => _capture(boundary, 'ai-review-390'));
      await tester.ensureVisible(find.text('付款方式'));
      await tester.pumpAndSettle();
      expect(find.text('个人垫付'), findsOneWidget);
      expect(find.text('共同钱包'), findsOneWidget);
      await tester.runAsync(() => _capture(boundary, 'ai-review-people-390'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.enterText(find.byType(TextField).first, '-5');
      await tester.tap(find.text('确认记账'));
      await tester.pumpAndSettle();
      expect(find.text('请输入大于 0 的有效金额'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('请输入大于 0 的有效金额'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        tester.getBottomLeft(find.text('确认记账')).dy,
        lessThanOrEqualTo(544),
      );
      expect(find.text('第 2/3 笔'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => _capture(boundary, 'ai-review-validation-keyboard-390'),
      );
    },
  );
  testWidgets('AI pending people and converted amount fit real Chinese font', (
    tester,
  ) async {
    final data = await _fixture();
    data.ledger.baseCurrencyCode = 'THB';
    data.ledger.exchangeRateToCNY = 0.2;
    final boundary = GlobalKey();
    await _mount(
      tester,
      data.database,
      boundary,
      Scaffold(
        body: AiDraftReview(
          draft: const AiDraft(
            sourceText: '王倾和陈欣喝饮料，花了三十元',
            type: 0,
            amount: 30,
            currencyCode: 'CNY',
            categorySuggestion: '餐饮',
            personUuids: [],
            unresolvedNames: ['王倾', '陈欣'],
            paymentMode: AiPaymentMode.unconfirmed,
            personMatches: [
              AiPersonMatch(
                sourceName: '王倾',
                role: 'participant',
                candidatePersonUuids: ['xiaowang'],
              ),
              AiPersonMatch(
                sourceName: '陈欣',
                role: 'payer',
                candidatePersonUuids: ['xiaoli'],
              ),
            ],
          ),
          ledger: data.ledger,
          people: data.people,
          position: 1,
          total: 1,
          busy: false,
          onConfirm: (_) async {},
          onSkip: () {},
        ),
      ),
      width: 390,
    );
    await tester.ensureVisible(find.text('付款方式待确认'));
    await tester.pumpAndSettle();
    expect(find.text('按账本汇率约合 THB 150.00'), findsOneWidget);
    expect(find.text('人员待确认，确认后显示分摊金额'), findsOneWidget);
    expect(find.textContaining('每人 CNY'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => _capture(boundary, 'ai-review-pending-390'));
  });
  testWidgets('bookkeeping and edit remain usable at large text size', (
    tester,
  ) async {
    final data = await _fixture();
    final boundary = GlobalKey();
    await _mount(
      tester,
      data.database,
      boundary,
      const HomePage(),
      width: 390,
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('bookkeeping-amount-input')),
      '-5',
    );
    await tester.tap(find.text('保存记账'));
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('请输入大于 0 的有效金额'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => _capture(boundary, 'bookkeeping-large-text-390'),
    );
    await tester.pumpWidget(const SizedBox());
    await _mount(
      tester,
      data.database,
      boundary,
      Scaffold(
        body: EditTransactionSheet(
          transaction: data.record,
          ledger: data.ledger,
        ),
      ),
      width: 390,
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, '-5');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('请输入大于 0 的有效金额'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => _capture(boundary, 'edit-large-text-390'));
  });
}

Future<
  ({
    DatabaseService database,
    Ledger ledger,
    List<Person> people,
    TransactionRecord record,
  })
>
_fixture() async {
  final database = DatabaseService();
  final ledger = Ledger()
    ..uuid = 'transaction-capture'
    ..name = '日常生活账本'
    ..baseCurrencyCode = 'CNY'
    ..personUuids = ['xiaowang', 'xiaoli'];
  await database.saveLedger(ledger);
  final people = [
    Person()
      ..uuid = 'xiaowang'
      ..name = '小王'
      ..avatar = 'W',
    Person()
      ..uuid = 'xiaoli'
      ..name = '小李'
      ..avatar = 'L',
  ];
  for (final person in people) {
    await database.savePerson(person);
  }
  final record = TransactionRecord()
    ..uuid = 'capture-dinner'
    ..ledgerUuid = ledger.uuid
    ..type = 0
    ..amount = 68
    ..currencyCode = 'CNY'
    ..category = '餐饮'
    ..note = '两个人的晚餐'
    ..personUuids = ['xiaowang', 'xiaoli']
    ..payerPersonUuid = 'xiaowang'
    ..createdAt = DateTime(2026, 9, 28, 18, 30);
  await database.saveTransaction(record);
  return (database: database, ledger: ledger, people: people, record: record);
}

Future<void> _mount(
  WidgetTester tester,
  DatabaseService database,
  GlobalKey boundary,
  Widget screen, {
  required double width,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        authTokenProvider.overrideWith((ref) async => null),
      ],
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: _realFontTheme(AppTheme.lightTheme),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(GlobalKey key, String name) async {
  if (_captureDir.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final folder = Directory(_captureDir);
  await folder.create(recursive: true);
  await File(
    '${folder.path}/$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

// Material controls use independent label styles. Give each the same real
// fallback font as body text so capture measurements include Chinese glyphs.
ThemeData _realFontTheme(ThemeData theme) {
  ButtonStyle realLabels(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStateProperty.resolveWith(
          (states) =>
              (style?.textStyle?.resolve(states) ?? theme.textTheme.labelLarge!)
                  .copyWith(fontFamily: 'Microsoft YaHei'),
        ),
      );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Microsoft YaHei'),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: 'Microsoft YaHei',
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: realLabels(theme.segmentedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: realLabels(theme.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: realLabels(theme.outlinedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: realLabels(theme.filledButtonTheme.style),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: theme.chipTheme.labelStyle?.copyWith(
        fontFamily: 'Microsoft YaHei',
      ),
      secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: 'Microsoft YaHei',
      ),
    ),
  );
}
