import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/di/providers.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/ledgers/presentation/screens/ledger_dashboard_page.dart';
import 'package:simon_ledger_flutter/features/statistics/presentation/widgets/statistics_tab.dart';

void main() {
  setUpAll(() async {
    final windowsDirectory = Platform.environment['WINDIR'];
    final font = File('${windowsDirectory ?? ''}/Fonts/msyh.ttc');
    if (Platform.isWindows && windowsDirectory != null && font.existsSync()) {
      final bytes = await font.readAsBytes();
      for (final family in ['Microsoft YaHei', 'Roboto', 'Ahem']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
    final executable = File(Platform.resolvedExecutable);
    var cacheDirectory = executable.parent.parent.parent;
    var icons = File(
      '${cacheDirectory.path}/artifacts/material_fonts/materialicons-regular.otf',
    );
    // flutter_tester sits deeper than dart.exe in the same SDK cache.
    if (!icons.existsSync()) {
      cacheDirectory = executable.parent;
      for (var level = 0; level < 6 && !icons.existsSync(); level++) {
        icons = File(
          '${cacheDirectory.path}/artifacts/material_fonts/materialicons-regular.otf',
        );
        cacheDirectory = cacheDirectory.parent;
      }
    }
    if (icons.existsSync()) {
      final bytes = await icons.readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  for (final width in [280.0, 390.0, 1280.0]) {
    testWidgets('populated statistics and ledger fit ${width.toInt()}px', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = DatabaseService();
      final ledger = Ledger()
        ..uuid = 'populated-ledger'
        ..name = '北海道秋日旅行'
        ..baseCurrencyCode = 'JPY'
        ..exchangeRateToCNY = 0.05
        ..personUuids = ['simon', 'alex'];
      await database.saveLedger(ledger);
      for (final (id, name, avatar) in [
        ('simon', 'Simon', 'S'),
        ('alex', 'Alex', 'A'),
      ]) {
        await database.savePerson(
          Person()
            ..uuid = id
            ..name = name
            ..avatar = avatar,
        );
      }
      final now = DateTime.now();
      for (final (id, category, note, amount, type, days) in [
        ('food', '餐饮', '札幌拉面和咖啡', 3600.0, 0, 0),
        ('hotel', '住宿', '小樽两晚民宿', 24000.0, 0, 0),
        ('bus', '交通', '机场巴士', 2200.0, 0, 0),
        ('shop', '购物', '伴手礼与明信片', 4800.0, 0, 0),
        ('refund', '退款', '退回车票押金', 1600.0, 1, 0),
        ('old-food', '餐饮', '上个月的一餐', 2800.0, 0, 35),
      ]) {
        await database.saveTransaction(
          TransactionRecord()
            ..uuid = id
            ..ledgerUuid = ledger.uuid
            ..category = category
            ..note = note
            ..amount = amount
            ..type = type
            ..currencyCode = 'JPY'
            ..personUuids = ['simon', 'alex']
            ..createdAt = DateTime(now.year, now.month, now.day - days, 10),
        );
      }
      final boundaryKey = GlobalKey();
      final theme = _realFontTheme(AppTheme.lightTheme);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            authTokenProvider.overrideWith((ref) async => null),
          ],
          child: RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: theme,
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: StatisticsTab(ledgers: [ledger])),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('北海道秋日旅行'), findsOneWidget);
      expect(find.byTooltip('上个月'), findsOneWidget);
      await tester.runAsync(
        () => _capture(boundaryKey, 'statistics-${width.toInt()}'),
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('statistics-category-餐饮')),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('statistics-category-餐饮'))),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-category-餐饮')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LedgerDashboardPage), findsOneWidget);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.text('札幌拉面和咖啡'), findsOneWidget);
      expect(find.text('小樽两晚民宿'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => _capture(boundaryKey, 'category-drilldown-${width.toInt()}'),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StatisticsTab), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => LedgerDashboardPage(ledger: ledger),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => _capture(boundaryKey, 'ledger-${width.toInt()}'),
      );
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -650),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        greaterThanOrEqualTo(0),
      );
      expect(tester.getTopLeft(find.byType(TextField)).dy, lessThan(160));
    });
  }
}

Future<void> _capture(GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_UI'] != '1') return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final folder = Directory(
    r'D:\workplace\projects\simon-ledger\.tmp\ux-review',
  );
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
