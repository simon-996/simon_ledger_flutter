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
import 'package:simon_ledger_flutter/core/repositories/ai_bookkeeping_repository.dart';
import 'package:simon_ledger_flutter/core/services/ai_draft_queue.dart';
import 'package:simon_ledger_flutter/core/services/ai_audio_recorder.dart';
import 'package:simon_ledger_flutter/features/transactions/presentation/widgets/ai_bookkeeping_flow.dart';

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
  Future<List<AiDraft>> parse(String ledgerUuid, String text, String zone) async { parseCalls++; return [
    const AiDraft(sourceText: '早餐18元', type: 0, amount: 18,
      currencyCode: 'CNY', categorySuggestion: '餐饮', personUuids: ['p1'], unresolvedNames: []),
    const AiDraft(sourceText: '午饭32元', type: 0, amount: 32,
      currencyCode: 'CNY', categorySuggestion: '餐饮', personUuids: ['p1'], unresolvedNames: []),
  ]; }
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
  Future<void> dispose() async { await chunks.close(); }
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

  testWidgets('reviews two AI drafts but only saves the confirmed entry', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final person = Person()..uuid = 'p1'..name = '小王';
    final queue = AiDraftQueue(scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => []);
    final saved = <AiDraftItem>[];

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiBookkeepingFlow(
      ledger: ledger,
      people: [person],
      queue: queue,
      repository: FakeRepository(),
      onSave: (item, draft) async { saved.add(item); },
    ))));
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
    expect(saved, hasLength(1));
    expect(await queue.load('ledger-1'), isEmpty);
  });

  testWidgets('shows editable transcript and does not parse until submitted', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final repository = FakeRepository();
    final device = FakeVoiceDevice();
    final recorder = AiAudioRecorder(device: device);
    final queue = AiDraftQueue(scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => []);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiBookkeepingFlow(
      ledger: ledger, people: const [], queue: queue, repository: repository,
      recorder: recorder, canTranscribe: true,
      onSave: (_, _) async {},
    ))));
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
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
    expect(find.text('录音为空，请重试'), findsNothing);
    expect(find.text('语音转写失败，可继续使用文字输入'), findsNothing);
    expect(repository.transcribeCalls, 1);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '早餐花了十八元');
    expect(repository.parseCalls, 0);
  });

  testWidgets('recording stop failure leaves text entry available', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY';
    final device = FakeVoiceDevice();
    final recorder = AiAudioRecorder(device: device);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiBookkeepingFlow(
      ledger: ledger, people: const [],
      queue: AiDraftQueue(scope: const LocalDataScope.account('alice'),
        loadTransactions: (_) async => []),
      repository: FakeRepository(), recorder: recorder, canTranscribe: true,
      onSave: (_, _) async {},
    ))));
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
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
    expect(find.text('录音结束失败，可继续使用文字输入'), findsOneWidget);
    expect(find.text('生成草稿'), findsOneWidget);
  });

  testWidgets('retry after draft cleanup failure does not save twice', (tester) async {
    final ledger = Ledger()
      ..uuid = 'ledger-1'
      ..name = '共享账本'
      ..baseCurrencyCode = 'CNY'
      ..personUuids = ['p1'];
    final saved = <TransactionRecord>[];
    final queue = FailOnceQueue(scope: const LocalDataScope.account('alice'),
      loadTransactions: (_) async => saved);
    final person = Person()..uuid = 'p1'..name = '小王';
    var saveCalls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiBookkeepingFlow(
      ledger: ledger, people: [person], queue: queue,
      repository: FakeRepository(),
      onSave: (item, _) async {
        saveCalls++;
        saved.add(TransactionRecord()
          ..uuid = item.uuid
          ..clientOperationId = item.operationId);
      },
    ))));
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
    expect(find.text('保存失败，草稿已保留，请重试'), findsOneWidget);

    await tester.ensureVisible(find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    expect(saveCalls, 1);
    expect(find.text('第 2/2 笔'), findsOneWidget);
  });
}
