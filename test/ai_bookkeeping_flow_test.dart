import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/ai_draft.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/network/api_exception.dart';
import 'package:simon_ledger_flutter/core/repositories/ai_bookkeeping_repository.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_queue.dart';
import 'package:simon_ledger_flutter/core/services/ai_audio_recorder.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_bookkeeping_flow.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_draft_review.dart';

class FakeRepository extends AiBookkeepingRepository {
  FakeRepository() : super(ApiClient(tokenStore: TokenStore()));

  int parseCalls = 0;
  int transcribeCalls = 0;

  @override
  Future<String> transcribe(String ledgerUuid, Uint8List pcm) async {
    transcribeCalls++;
    return '早餐花了十八元';
  }

  @override
  Future<List<AiDraft>> parse(
    String ledgerUuid,
    String text,
    String zone, {
    int schemaVersion = 1,
    List<String> expenseCategories = const [],
    List<String> incomeCategories = const [],
  }) async {
    parseCalls++;
    return [
      const AiDraft(
        sourceText: '早餐18元',
        type: 0,
        amount: 18,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        personUuids: ['p1'],
        unresolvedNames: [],
        paymentMode: 'SHARED_POOL',
        participantScope: 'SPECIFIED',
      ),
      const AiDraft(
        sourceText: '午饭32元',
        type: 0,
        amount: 32,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        personUuids: ['p1'],
        unresolvedNames: [],
        paymentMode: 'SHARED_POOL',
        participantScope: 'SPECIFIED',
      ),
    ];
  }
}

class SlowRepository extends FakeRepository {
  final response = Completer<List<AiDraft>>();

  @override
  Future<List<AiDraft>> parse(
    String ledgerUuid,
    String text,
    String zone, {
    int schemaVersion = 1,
    List<String> expenseCategories = const [],
    List<String> incomeCategories = const [],
  }) => response.future;
}

class SemanticRepository extends FakeRepository {
  SemanticRepository(this.drafts);

  final List<AiDraft> drafts;
  int? lastSchemaVersion;

  @override
  Future<List<AiDraft>> parse(
    String ledgerUuid,
    String text,
    String zone, {
    int schemaVersion = 1,
    List<String> expenseCategories = const [],
    List<String> incomeCategories = const [],
  }) async {
    parseCalls++;
    lastSchemaVersion = schemaVersion;
    return drafts;
  }
}

class FakeVoiceDevice implements AiRecorderDevice {
  final chunks = StreamController<Uint8List>.broadcast();
  bool failStop = false;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<Stream<Uint8List>> startPcmStream() async => chunks.stream;
  @override
  Future<void> stop() async {
    if (failStop) throw StateError('device failed');
  }

  @override
  Future<void> dispose() async {
    await chunks.close();
  }
}

class FailOnceQueue extends AiDraftQueue {
  FailOnceQueue({required super.scope, required super.loadTransactions});
  bool failRemove = true;

  @override
  Future<void> remove(String ledgerUuid, String uuid) async {
    if (failRemove) {
      failRemove = false;
      throw StateError('local storage temporarily unavailable');
    }
    await super.remove(ledgerUuid, uuid);
  }
}

class FailClearInputQueue extends AiDraftQueue {
  FailClearInputQueue({required super.scope, required super.loadTransactions});
  bool failClear = true;

  @override
  Future<void> writeInput(String ledgerUuid, String text) async {
    if (text.isEmpty && failClear) {
      failClear = false;
      throw StateError('input cleanup unavailable');
    }
    await super.writeInput(ledgerUuid, text);
  }
}

class FailFirstEditQueue extends AiDraftQueue {
  FailFirstEditQueue({required super.scope, required super.loadTransactions});
  bool failFirst = true;
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();

  @override
  Future<void> update(
    String ledgerUuid,
    String uuid,
    AiDraft draft, {
    String? amountInput,
  }) async {
    if (failFirst) {
      failFirst = false;
      firstStarted.complete();
      await releaseFirst.future;
      throw StateError('temporary failure');
    }
    await super.update(ledgerUuid, uuid, draft, amountInput: amountInput);
  }
}

class SlowInputQueue extends AiDraftQueue {
  SlowInputQueue({required super.scope, required super.loadTransactions});
  final release = Completer<void>();

  @override
  Future<void> writeInput(String ledgerUuid, String text) async {
    await release.future;
    await super.writeInput(ledgerUuid, text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('AI entry requires an account and cloud ledger write access', () {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    expect(isAiBookkeepingEligible(ledger, true), isFalse);
    ledger.cloudPolicy = LedgerCloudPolicy.cloudManaged;
    ledger.role = 'viewer';
    expect(isAiBookkeepingEligible(ledger, true), isFalse);
    ledger.role = 'editor';
    expect(isAiBookkeepingEligible(ledger, false), isFalse);
    expect(isAiBookkeepingEligible(ledger, true), isTrue);
  });

  test('parse uses the device time zone offset', () {
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    expect(
      currentAiTimeZone(),
      '$sign${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}',
    );
  });

  test('AI quota errors remain distinguishable from missing permission', () {
    expect(
      aiBookkeepingErrorMessage(
        const ApiException(code: 403001, message: '今日 AI 记账次数已用完'),
      ),
      '今日 AI 记账次数已用完',
    );
  });

  testWidgets('reviews two AI drafts but only saves the confirmed entry', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    final saved = <AiDraftItem>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: [person],
            queue: queue,
            repository: FakeRepository(),
            onSave: (item, draft) async {
              saved.add(item);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '早餐18元，午饭32元');
    await tester.tap(find.text('生成草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(find.text('第 1/2 笔'), findsOneWidget);
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(find.text('第 2/2 笔'), findsOneWidget);
    await tester.ensureVisible(find.text('跳过此笔'));
    await tester.tap(find.text('跳过此笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定跳过'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(await queue.load('ledger-1'), isEmpty);
  });

  testWidgets('v2 summary keeps edits by draft and preserves batch order', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    AiDraft v2Draft(String source, double amount) => AiDraft(
      sourceText: source,
      type: 0,
      amount: amount,
      currencyCode: 'CNY',
      categorySuggestion: '餐饮',
      happenedAt: DateTime.now(),
      personUuids: const ['p1'],
      unresolvedNames: const [],
      schemaVersion: 2,
      paymentMode: 'SHARED_POOL',
      participantScope: 'SPECIFIED',
    );

    final items = await queue.add('ledger-1', [
      v2Draft('早餐18元', 18),
      v2Draft('午饭32元', 32),
    ]);
    final savedAmounts = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: [person],
            queue: queue,
            repository: FakeRepository(),
            onSave: (_, draft) async => savedAmounts.add(draft.amount),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1/2 笔'), findsOneWidget);
    expect(find.text('第 2 笔'), findsOneWidget);
    expect(find.byKey(ValueKey('summary-${items.first.uuid}')), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey('ai-draft-overview-${items[1].uuid}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 2/2 笔'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('summary-${items[1].uuid}')),
        matching: find.text('CNY 32.00'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ai-summary-edit-amount')));
    await tester.pumpAndSettle();
    expect(find.text('返回摘要'), findsOneWidget);
    expect(find.text('展开全部字段'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '金额'), '50');
    await tester.pump();
    await tester.tap(find.text('返回摘要'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('ai-draft-overview-${items.first.uuid}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(ValueKey('summary-${items.first.uuid}')),
        matching: find.text('CNY 18.00'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(ValueKey('ai-draft-overview-${items[1].uuid}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(ValueKey('summary-${items[1].uuid}')),
        matching: find.text('CNY 50.00'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(savedAmounts, [50]);
    expect(find.text('第 1/2 笔'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('summary-${items.first.uuid}')),
        matching: find.text('CNY 18.00'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(savedAmounts, [50, 18]);
    expect(await queue.load('ledger-1'), isEmpty);
  });

  testWidgets('the accommodation example is fully prefilled and saves once', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '旅行账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1', 'p2'];
    final people = [
      Person()
        ..uuid = 'p1'
        ..name = '张三',
      Person()
        ..uuid = 'p2'
        ..name = '李四',
    ];
    final repository = SemanticRepository([
      AiDraft(
        sourceText: '张三在昨天住宿花了400元，他垫付的，所有人都用上了。',
        type: 0,
        amount: 400,
        currencyCode: 'CNY',
        categorySuggestion: '居住',
        categoryOriginalSuggestion: '住宿',
        note: '住宿费用',
        happenedAt: DateTime.now().subtract(const Duration(days: 1)),
        payerPersonUuid: 'p1',
        personUuids: const ['p1', 'p2'],
        unresolvedNames: const [],
        schemaVersion: 2,
        paymentMode: 'PERSON_PAID',
        participantScope: 'ALL',
        splitMode: 'EQUAL',
        fieldSources: const {
          'amount': 'EXPLICIT',
          'category': 'SUGGESTED',
          'happenedAt': 'EXPLICIT',
          'payer': 'EXPLICIT',
          'participants': 'EXPLICIT',
          'splitMode': 'DEFAULT',
        },
      ),
    ]);
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    AiDraft? saved;
    var saveCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: people,
            queue: queue,
            repository: repository,
            draftSchemaVersion: 2,
            onSave: (_, draft) async {
              saveCalls++;
              saved = draft;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '张三在昨天住宿花了400元，他垫付的，所有人都用上了。',
    );
    await tester.tap(find.text('生成草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(repository.lastSchemaVersion, 2);
    expect(find.text('400'), findsNothing);
    expect(find.text('CNY 400.00'), findsOneWidget);
    expect(find.text('张三垫付'), findsOneWidget);
    expect(find.text('全体 2 人承担'), findsOneWidget);
    expect(find.text('默认均摊 · 约 CNY 200.00/人'), findsOneWidget);
    expect(find.text('展开全部字段'), findsNothing);
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();

    expect(saveCalls, 1);
    expect(saved?.categorySuggestion, '居住');
    expect(saved?.payerPersonUuid, 'p1');
    expect(saved?.personUuids, ['p1', 'p2']);
    expect(saved?.paymentMode, 'PERSON_PAID');
    expect(saved?.participantScope, 'ALL');
    expect(
      saved?.happenedAt?.day,
      DateTime.now().subtract(const Duration(days: 1)).day,
    );
  });

  testWidgets('shows editable transcript and does not parse until submitted', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final repository = FakeRepository();
    final device = FakeVoiceDevice();
    final recorder = AiAudioRecorder(device: device);
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: const [],
            queue: queue,
            repository: repository,
            recorder: recorder,
            canTranscribe: true,
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始语音输入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(recorder.isRecording, isTrue);
    device.chunks.add(Uint8List.fromList([1, 2, 3, 4]));
    await tester.pumpAndSettle();
    expect(recorder.isRecording, isTrue);
    await tester.tap(find.text('结束录音并转写'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    expect(find.text('录音为空，请重试'), findsNothing);
    expect(find.text('语音转写失败，可继续使用文字输入'), findsNothing);
    expect(repository.transcribeCalls, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '早餐花了十八元',
    );
    expect(repository.parseCalls, 0);
  });

  testWidgets('recording stop failure leaves text entry available', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final device = FakeVoiceDevice();
    final recorder = AiAudioRecorder(device: device);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: const [],
            queue: AiDraftQueue(
              scope: const LocalDataScope.account('alice'),
              loadTransactions: (_) async => [],
            ),
            repository: FakeRepository(),
            recorder: recorder,
            canTranscribe: true,
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始语音输入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(recorder.isRecording, isTrue);
    expect(find.text('结束录音并转写'), findsOneWidget);
    device.failStop = true;
    await tester.ensureVisible(find.text('结束录音并转写'));
    await tester.tap(find.text('结束录音并转写'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    expect(find.text('录音结束失败，可继续使用文字输入'), findsOneWidget);
    expect(find.text('生成草稿'), findsOneWidget);
  });

  testWidgets('retry after draft cleanup failure does not save twice', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final saved = <TransactionRecord>[];
    final queue = FailOnceQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => saved,
    );
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    var saveCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: [person],
            queue: queue,
            repository: FakeRepository(),
            onSave: (item, _) async {
              saveCalls++;
              saved.add(
                TransactionRecord()
                  ..uuid = item.uuid
                  ..clientOperationId = item.operationId,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '早餐18元，午饭32元');
    await tester.tap(find.text('生成草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saveCalls, 1);
    expect(find.text('流水已保存，草稿整理失败；重试会先核对已保存流水'), findsOneWidget);

    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saveCalls, 1);
    expect(find.text('第 2/2 笔'), findsOneWidget);
  });

  testWidgets(
    'review requires explicit category and unresolved person decisions',
    (tester) async {
      final ledger = Ledger()
        ..uuid = 'ledger-1'
        ..name = '共享账本'
        ..baseCurrencyCode = 'CNY'
        ..personUuids = ['p1'];
      final person = Person()
        ..uuid = 'p1'
        ..name = '小王';
      AiDraft? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiDraftReview(
              draft: const AiDraft(
                sourceText: '小王和小李吃饭',
                type: 0,
                amount: 18,
                currencyCode: 'CNY',
                categorySuggestion: '模型自造分类',
                personUuids: ['p1'],
                unresolvedNames: ['小李'],
              ),
              ledger: ledger,
              people: [person],
              position: 2,
              total: 3,
              busy: false,
              onConfirm: (draft) async {
                confirmed = draft;
              },
              onSkip: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 2/3 笔'), findsOneWidget);
      expect(find.text('金额与类型'), findsOneWidget);
      expect(find.text('分类与时间'), findsOneWidget);
      expect(find.textContaining('模型自造分类'), findsOneWidget);
      await tester.ensureVisible(find.text('确认记账'));
      await tester.tap(find.text('确认记账'));
      await tester.pumpAndSettle();
      expect(confirmed, isNull);
      expect(find.text('请选择分类'), findsOneWidget);
      expect(find.text('请确认待识别姓名和付款方式'), findsOneWidget);
      await tester.ensureVisible(find.text('餐饮'));
      await tester.tap(find.text('餐饮'));
      await tester.ensureVisible(find.text('忽略小李'));
      await tester.tap(find.text('忽略小李'));
      await tester.ensureVisible(find.text('确认记账'));
      await tester.tap(find.text('确认记账'));
      await tester.pumpAndSettle();
      expect(confirmed, isNull);
      await tester.ensureVisible(find.text('使用共同钱包'));
      await tester.tap(find.text('使用共同钱包'));
      await tester.ensureVisible(find.text('确认记账'));
      await tester.tap(find.text('确认记账'));
      await tester.pumpAndSettle();
      expect(confirmed?.categorySuggestion, '餐饮');
    },
  );

  testWidgets('payer choice stays separate from participant choice', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1', 'p2'];
    final people = [
      Person()
        ..uuid = 'p1'
        ..name = '张三',
      Person()
        ..uuid = 'p2'
        ..name = '李四',
    ];
    AiDraft? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: AiDraft(
              sourceText: '张三和李四昨天住宿400元，李四垫付',
              type: 0,
              amount: 400,
              currencyCode: 'CNY',
              categorySuggestion: '居住',
              personUuids: const ['p1'],
              unresolvedNames: const [],
              schemaVersion: 2,
              paymentMode: 'UNKNOWN',
              participantScope: 'SPECIFIED',
              happenedAt: DateTime(2026, 10, 4),
            ),
            ledger: ledger,
            people: people,
            position: 1,
            total: 1,
            busy: false,
            onConfirm: (draft) async => confirmed = draft,
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paymentChips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(paymentChips.map((chip) => chip.selected), everyElement(isFalse));
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);

    await tester.ensureVisible(find.text('个人垫付'));
    await tester.tap(find.text('个人垫付'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    expect(
      tester
          .widget<AppPersonChoiceGrid>(find.byType(AppPersonChoiceGrid).first)
          .selectedIds,
      {'p1'},
    );

    final payerGrid = find.byType(AppPersonChoiceGrid).at(1);
    await tester.tap(
      find.descendant(
        of: payerGrid,
        matching: find.byKey(const ValueKey('person-choice-tile-p2')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();

    expect(confirmed?.paymentMode, 'PERSON_PAID');
    expect(confirmed?.payerPersonUuid, 'p2');
    expect(confirmed?.personUuids, ['p1']);
  });

  testWidgets('unknown participant scope needs a deliberate snapshot choice', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1', 'p2'];
    final people = [
      Person()
        ..uuid = 'p1'
        ..name = '张三',
      Person()
        ..uuid = 'p2'
        ..name = '李四',
    ];
    AiDraft? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: AiDraft(
              sourceText: '住宿400元，大家都用上了',
              type: 0,
              amount: 400,
              currencyCode: 'CNY',
              categorySuggestion: '居住',
              personUuids: const ['p1', 'p2'],
              unresolvedNames: const [],
              schemaVersion: 2,
              paymentMode: 'SHARED_POOL',
              participantScope: 'UNKNOWN',
              happenedAt: DateTime(2026, 10, 4),
            ),
            ledger: ledger,
            people: people,
            position: 1,
            total: 1,
            busy: false,
            onConfirm: (draft) async => confirmed = draft,
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);

    await tester.ensureVisible(find.text('按当前名单确认承担人员'));
    await tester.tap(find.text('按当前名单确认承担人员'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed?.personUuids, ['p1', 'p2']);
    expect(confirmed?.participantScope, 'SPECIFIED');
    expect(confirmed?.paymentMode, 'SHARED_POOL');
    expect(confirmed?.payerPersonUuid, isNull);
  });

  testWidgets('non-equal split requires an explicit equal-split override', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '张三';
    AiDraft? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: AiDraft(
              sourceText: '房费400，张三承担300，李四承担100',
              type: 0,
              amount: 400,
              currencyCode: 'CNY',
              categorySuggestion: '居住',
              personUuids: const ['p1'],
              unresolvedNames: const [],
              schemaVersion: 2,
              paymentMode: 'SHARED_POOL',
              participantScope: 'SPECIFIED',
              splitMode: 'UNSUPPORTED',
              happenedAt: DateTime(2026, 10, 4),
              issues: const [
                AiDraftIssue(
                  id: 'split',
                  field: 'splitMode',
                  code: 'UNSUPPORTED_SPLIT',
                ),
              ],
            ),
            ledger: ledger,
            people: [person],
            position: 1,
            total: 1,
            busy: false,
            onConfirm: (draft) async => confirmed = draft,
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);

    await tester.ensureVisible(find.text('我确认改为等额分摊'));
    await tester.tap(find.text('我确认改为等额分摊'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed?.splitMode, 'EQUAL');
    expect(confirmed?.issues, isEmpty);
    expect(confirmed?.fieldSources['splitMode'], 'USER');
  });

  testWidgets('unsupported currency requires explicit ledger-currency choice', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '张三';
    AiDraft? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: AiDraft(
              sourceText: '住宿400欧元，全体使用，共同钱包支付',
              type: 0,
              amount: 400,
              currencyCode: 'EUR',
              categorySuggestion: '居住',
              personUuids: const ['p1'],
              unresolvedNames: const [],
              schemaVersion: 2,
              paymentMode: 'SHARED_POOL',
              participantScope: 'SPECIFIED',
              happenedAt: DateTime(2026, 10, 4),
              issues: const [
                AiDraftIssue(
                  id: 'currency',
                  field: 'currencyCode',
                  code: 'CURRENCY_UNSUPPORTED',
                ),
              ],
            ),
            ledger: ledger,
            people: [person],
            position: 1,
            total: 1,
            busy: false,
            onConfirm: (draft) async => confirmed = draft,
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);

    const choice = '按账本币种 CNY 继续（不换算金额）';
    await tester.ensureVisible(find.text(choice));
    await tester.tap(find.text(choice));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed?.currencyCode, 'CNY');
    expect(confirmed?.amount, 400);
    expect(confirmed?.issues, isEmpty);
    expect(confirmed?.fieldSources['currencyCode'], 'USER');
  });

  testWidgets('resolving an exclusion makes the participant list explicit', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1', 'p2'];
    final people = [
      Person()
        ..uuid = 'p1'
        ..name = '张三',
      Person()
        ..uuid = 'p2'
        ..name = '李四',
    ];
    AiDraft? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: AiDraft(
              sourceText: '住宿400，所有人使用，除小陈外',
              type: 0,
              amount: 400,
              currencyCode: 'CNY',
              categorySuggestion: '居住',
              personUuids: const ['p1', 'p2'],
              unresolvedNames: const [],
              schemaVersion: 2,
              paymentMode: 'SHARED_POOL',
              participantScope: 'ALL',
              happenedAt: DateTime(2026, 10, 4),
              issues: const [
                AiDraftIssue(
                  id: 'excluded',
                  field: 'excludedParticipants',
                  code: 'PERSON_NOT_FOUND',
                  sourceText: '小陈',
                ),
              ],
            ),
            ledger: ledger,
            people: people,
            position: 1,
            total: 1,
            busy: false,
            onConfirm: (draft) async => confirmed = draft,
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-issue-choice-excluded')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-issue-choice-excluded')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('李四').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();

    expect(confirmed?.participantScope, 'SPECIFIED');
    expect(confirmed?.personUuids, ['p1']);
    expect(confirmed?.fieldSources['participants'], 'USER');
  });

  testWidgets('edits to a review survive closing and reopening the flow', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    await queue.add('ledger-1', [
      const AiDraft(
        sourceText: '早餐',
        type: 0,
        amount: 18,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        personUuids: ['p1'],
        unresolvedNames: [],
        paymentMode: 'SHARED_POOL',
        participantScope: 'SPECIFIED',
      ),
    ]);
    Widget flow(Key key) => MaterialApp(
      home: Scaffold(
        body: AiBookkeepingFlow(
          key: key,
          ledger: ledger,
          people: [person],
          queue: queue,
          repository: FakeRepository(),
          onSave: (_, _) async {},
        ),
      ),
    );
    await tester.pumpWidget(flow(const ValueKey('first')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '金额'), '27.50');
    await tester.pumpAndSettle();
    await tester.pumpWidget(flow(const ValueKey('second')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '金额'))
          .controller
          ?.text,
      '27.50',
    );
    await tester.enterText(find.widgetWithText(TextField, '金额'), '27.');
    await tester.pumpAndSettle();
    await tester.pumpWidget(flow(const ValueKey('third')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '金额'))
          .controller
          ?.text,
      '27.',
    );
  });

  testWidgets('shows original batch progress and asks before skipping', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    final items = await queue.add('ledger-1', [
      const AiDraft(
        sourceText: '早餐',
        type: 0,
        amount: 18,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        personUuids: ['p1'],
        unresolvedNames: [],
      ),
      const AiDraft(
        sourceText: '午饭',
        type: 0,
        amount: 32,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        personUuids: ['p1'],
        unresolvedNames: [],
      ),
    ]);
    await queue.remove('ledger-1', items.first.uuid);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: [person],
            queue: queue,
            repository: FakeRepository(),
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 2/2 笔'), findsOneWidget);
    expect(find.textContaining('午饭'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.getBottomLeft(find.text('确认记账')).dy, lessThan(600));
    await tester.tap(find.text('跳过此笔'));
    await tester.pumpAndSettle();
    expect(find.text('确定跳过这笔草稿？'), findsOneWidget);
    await tester.tap(find.text('继续复核'));
    await tester.pumpAndSettle();
    expect(await queue.load('ledger-1'), hasLength(1));
  });

  testWidgets('close summarizes confirmed skipped and pending drafts', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    await queue.add('ledger-1', [
      const AiDraft(
        sourceText: '早餐',
        type: 0,
        amount: 18,
        currencyCode: 'CNY',
        personUuids: [],
        unresolvedNames: [],
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: const [],
            queue: queue,
            repository: FakeRepository(),
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭 AI 记账'));
    await tester.pumpAndSettle();
    expect(find.textContaining('剩余 1 笔'), findsOneWidget);
    expect(find.text('稍后继续'), findsOneWidget);
    await tester.tap(find.text('稍后继续'));
    await tester.pumpAndSettle();
    expect(find.byType(AiBookkeepingFlow), findsNothing);
    expect(await queue.load('ledger-1'), hasLength(1));
  });

  testWidgets(
    'recording shows time and blocks parsing until transcription ends',
    (tester) async {
      final ledger = Ledger()
        ..uuid = 'ledger-1'
        ..name = '共享账本'
        ..baseCurrencyCode = 'CNY';
      final device = FakeVoiceDevice();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiBookkeepingFlow(
              ledger: ledger,
              people: const [],
              queue: AiDraftQueue(
                scope: const LocalDataScope.account('alice'),
                loadTransactions: (_) async => [],
              ),
              repository: FakeRepository(),
              recorder: AiAudioRecorder(device: device),
              canTranscribe: true,
              onSave: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始语音输入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意并继续'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('录音中 00:02 / 01:00'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '生成草稿'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('transcript asks before replacing existing text', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final device = FakeVoiceDevice();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: const [],
            queue: AiDraftQueue(
              scope: const LocalDataScope.account('alice'),
              loadTransactions: (_) async => [],
            ),
            repository: FakeRepository(),
            recorder: AiAudioRecorder(device: device),
            canTranscribe: true,
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '昨天的晚餐 48 元');
    await tester.tap(find.text('开始语音输入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    device.chunks.add(Uint8List.fromList([1, 2, 3, 4]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束录音并转写'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    expect(find.text('替换已有文字？'), findsOneWidget);
    await tester.tap(find.text('保留原文'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '昨天的晚餐 48 元',
    );
  });

  testWidgets('text cannot change while a parse request is pending', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final repository = SlowRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: const [],
            queue: AiDraftQueue(
              scope: const LocalDataScope.account('alice'),
              loadTransactions: (_) async => [],
            ),
            repository: repository,
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '早餐十八元');
    await tester.tap(find.text('生成草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      isFalse,
    );
    repository.response.complete([
      const AiDraft(
        sourceText: '早餐十八元',
        type: 0,
        amount: 18,
        currencyCode: 'CNY',
        personUuids: [],
        unresolvedNames: [],
      ),
    ]);
    await tester.pumpAndSettle();
  });

  testWidgets('review actions stay visible on a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1', 'p2'];
    final people = [
      Person()
        ..uuid = 'p1'
        ..name = '小王',
      Person()
        ..uuid = 'p2'
        ..name = '小李',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: AiDraftReview(
              draft: const AiDraft(
                sourceText: '昨天午饭小王和小李一起吃了 68 元，小王付款',
                type: 0,
                amount: 68,
                currencyCode: 'CNY',
                categorySuggestion: '餐饮',
                personUuids: ['p1', 'p2'],
                unresolvedNames: [],
              ),
              ledger: ledger,
              people: people,
              position: 2,
              total: 5,
              busy: false,
              onConfirm: (_) async {},
              onSkip: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('第 2/5 笔'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('确认记账')).dy, lessThan(844));
  });

  testWidgets('drafts remain reviewable if clearing source text fails', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final queue = FailClearInputQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: const [],
            queue: queue,
            repository: FakeRepository(),
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '早餐18元，午饭32元');
    await tester.tap(find.text('生成草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/2 笔'), findsOneWidget);
    expect(await queue.load('ledger-1'), hasLength(2));
  });

  testWidgets('stale participant and payer require an explicit decision', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    AiDraft? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: const AiDraft(
              sourceText: '旧人员参与的午饭',
              type: 0,
              amount: 18,
              currencyCode: 'CNY',
              categorySuggestion: '餐饮',
              personUuids: ['p1', 'removed-person'],
              unresolvedNames: [],
              payerPersonUuid: 'removed-person',
            ),
            ledger: ledger,
            people: [person],
            position: 1,
            total: 1,
            busy: false,
            onConfirm: (draft) async {
              confirmed = draft;
            },
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('原参与人已失效'), findsWidgets);
    expect(find.textContaining('原付款人已失效'), findsWidgets);
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
  });

  testWidgets('old AI dates still open the date picker', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReview(
            draft: AiDraft(
              sourceText: '旧日期',
              type: 0,
              amount: 18,
              currencyCode: 'CNY',
              categorySuggestion: '餐饮',
              happenedAt: DateTime(1999, 12, 31),
              personUuids: const ['p1'],
              unresolvedNames: const [],
            ),
            ledger: ledger,
            people: [person],
            position: 1,
            total: 1,
            busy: false,
            onConfirm: (_) async {},
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('1999-12-31'));
    await tester.tap(find.textContaining('1999-12-31'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(DateUtils.isSameDay(picker.lastDate, DateTime.now()), isTrue);
  });

  testWidgets('review flow closes from a real bottom sheet route', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final queue = AiDraftQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: false,
                  enableDrag: false,
                  builder: (_) => SizedBox(
                    height: 600,
                    child: AiBookkeepingFlow(
                      ledger: ledger,
                      people: const [],
                      queue: queue,
                      repository: FakeRepository(),
                      onSave: (_, _) async {},
                    ),
                  ),
                ),
                child: const Text('打开 AI 记账'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI 记账'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭 AI 记账'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后继续'));
    await tester.pumpAndSettle();
    expect(find.byType(AiBookkeepingFlow), findsNothing);
  });

  testWidgets('a later successful edit clears an earlier save failure', (
    tester,
  ) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()
      ..uuid = 'p1'
      ..name = '小王';
    final queue = FailFirstEditQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    await queue.add('ledger-1', [
      const AiDraft(
        sourceText: '早餐',
        type: 0,
        amount: 18,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        personUuids: ['p1'],
        unresolvedNames: [],
        paymentMode: 'SHARED_POOL',
        participantScope: 'SPECIFIED',
      ),
    ]);
    AiDraft? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiBookkeepingFlow(
            ledger: ledger,
            people: [person],
            queue: queue,
            repository: FakeRepository(),
            onSave: (_, draft) async {
              saved = draft;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '金额'), '19');
    await tester.pump();
    await queue.firstStarted.future;
    await tester.enterText(find.widgetWithText(TextField, '金额'), '20');
    queue.releaseFirst.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saved?.amount, 20);
  });

  testWidgets('close waits for pending input persistence', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final queue = SlowInputQueue(
      scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: false,
                  enableDrag: false,
                  builder: (_) => SizedBox(
                    height: 600,
                    child: AiBookkeepingFlow(
                      ledger: ledger,
                      people: const [],
                      queue: queue,
                      repository: FakeRepository(),
                      onSave: (_, _) async {},
                    ),
                  ),
                ),
                child: const Text('打开 AI 记账'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI 记账'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '晚餐 42 元');
    await tester.tap(find.byTooltip('关闭 AI 记账'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后继续'));
    await tester.pumpAndSettle();
    expect(find.byType(AiBookkeepingFlow), findsOneWidget);
    queue.release.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AiBookkeepingFlow), findsNothing);
    expect(await queue.readInput('ledger-1'), '晚餐 42 元');
  });
}
