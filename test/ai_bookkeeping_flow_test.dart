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
    String zone,
  ) async {
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
      ),
      const AiDraft(
        sourceText: '午饭32元',
        type: 0,
        amount: 32,
        currencyCode: 'CNY',
        categorySuggestion: '餐饮',
        personUuids: ['p1'],
        unresolvedNames: [],
      ),
    ];
  }
}

class SlowRepository extends FakeRepository {
  final response = Completer<List<AiDraft>>();

  @override
  Future<List<AiDraft>> parse(String ledgerUuid, String text, String zone) =>
      response.future;
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
