import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/repositories/ai_bookkeeping_repository.dart';
import '../../../../core/services/ai_draft_queue.dart';
import '../../../../core/services/ai_audio_recorder.dart';
import 'ai_draft_review.dart';

bool isAiBookkeepingEligible(Ledger ledger, bool signedIn) =>
    signedIn && ledger.isCloudManaged && ledger.canRecordTransactions;

class AiBookkeepingFlow extends StatefulWidget {
  const AiBookkeepingFlow({
    super.key,
    required this.ledger,
    required this.people,
    required this.queue,
    required this.repository,
    required this.onSave,
    this.canParse = true,
    this.canTranscribe = false,
    this.recorder,
  });

  final Ledger ledger;
  final List<Person> people;
  final AiDraftQueue queue;
  final AiBookkeepingRepository repository;
  final Future<void> Function(AiDraftItem item, AiDraft draft) onSave;
  final bool canParse;
  final bool canTranscribe;
  final AiAudioRecorder? recorder;

  @override
  State<AiBookkeepingFlow> createState() => _AiBookkeepingFlowState();
}

class _AiBookkeepingFlowState extends State<AiBookkeepingFlow> {
  final _text = TextEditingController();
  List<AiDraftItem> _items = [];
  int _processed = 0;
  int _total = 0;
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  late final AiAudioRecorder _recorder;
  bool _recording = false;
  bool _voiceBusy = false;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? AiAudioRecorder();
    _restore();
  }

  Future<void> _restore() async {
    final text = await widget.queue.readInput(widget.ledger.uuid);
    final items = await widget.queue.load(widget.ledger.uuid);
    if (!mounted) return;
    _text.text = text;
    setState(() {
      _items = items;
      _total = items.length;
      _loaded = true;
    });
  }

  Future<bool> _confirmDisclosure({bool voice = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai_bookkeeping_disclosure.v1.${widget.queue.scope.storageKey}.${voice ? 'voice' : 'text'}';
    if (prefs.getBool(key) == true) return true;
    if (!mounted) return false;
    final accepted = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(
        title: const Text('使用 AI 记账'),
        content: Text(voice
          ? '录音将发送给腾讯云语音识别，返回的文字可编辑。提交文字后会发送给 DeepSeek 解析。系统不会自动保存流水。'
          : '你输入的记账描述会发送给第三方 AI 服务解析。系统只生成草稿；请核对金额、人员和分类后逐笔确认。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('同意并继续')),
        ],
      ));
    if (accepted != true) return false;
    await prefs.setBool(key, true);
    return true;
  }

  Future<void> _startRecording() async {
    if (_voiceBusy || _recording || !widget.canTranscribe) return;
    if (!await _confirmDisclosure(voice: true)) return;
    try {
      final allowed = await _recorder.start(onAutoStop: (bytes) {
        if (!mounted) { bytes.fillRange(0, bytes.length, 0); return; }
        setState(() => _recording = false);
        unawaited(_upload(bytes));
      });
      if (!mounted) return;
      setState(() {
        _recording = allowed;
        _error = allowed ? null : '未获得麦克风权限，可继续使用文字输入';
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法开始录音，可继续使用文字输入');
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (!_recording || _voiceBusy) return;
    try {
      final bytes = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      await _upload(bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = '录音结束失败，可继续使用文字输入';
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    try {
      final bytes = await _recorder.stop();
      bytes.fillRange(0, bytes.length, 0);
    } catch (_) {
      if (mounted) setState(() => _error = '取消录音失败，可继续使用文字输入');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _upload(Uint8List bytes) async {
    if (_voiceBusy) { bytes.fillRange(0, bytes.length, 0); return; }
    if (bytes.isEmpty) {
      if (mounted) setState(() => _error = '录音为空，请重试');
      return;
    }
    if (mounted) setState(() { _voiceBusy = true; _error = null; });
    try {
      final transcript = await widget.repository.transcribe(widget.ledger.remoteSyncUuid, bytes);
      if (!mounted) return;
      _text.text = transcript;
      await widget.queue.writeInput(widget.ledger.uuid, transcript);
    } catch (_) {
      if (mounted) setState(() => _error = '语音转写失败，可继续使用文字输入');
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _parse() async {
    if (_busy || !widget.canParse) return;
    final input = _text.text.trim();
    if (input.isEmpty || input.runes.length > 1000) {
      setState(() => _error = '请输入 1 到 1000 字的记账描述');
      return;
    }
    if (!await _confirmDisclosure()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.queue.writeInput(widget.ledger.uuid, input);
      final drafts = await widget.repository.parse(
        widget.ledger.remoteSyncUuid, input, 'Asia/Shanghai',
      );
      final items = await widget.queue.add(widget.ledger.uuid, drafts);
      await widget.queue.writeInput(widget.ledger.uuid, '');
      if (!mounted) return;
      _text.clear();
      setState(() {
        _items = items;
        _processed = 0;
        _total = items.length;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '解析失败，输入已保留，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(AiDraft draft) async {
    if (_busy || _items.isEmpty) return;
    final item = _items.first;
    setState(() { _busy = true; _error = null; });
    try {
      if (!await widget.queue.isSaved(widget.ledger.uuid, item)) {
        await widget.onSave(item, draft);
      }
      await widget.queue.remove(widget.ledger.uuid, item.uuid);
      final remaining = await widget.queue.load(widget.ledger.uuid);
      if (!mounted) return;
      setState(() { _items = remaining; _processed++; });
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，草稿已保留，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    if (_busy || _items.isEmpty) return;
    final item = _items.first;
    await widget.queue.remove(widget.ledger.uuid, item.uuid);
    final remaining = await widget.queue.load(widget.ledger.uuid);
    if (!mounted) return;
    setState(() { _items = remaining; _processed++; });
  }

  @override
  void dispose() {
    _text.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('AI 记账 · ${widget.ledger.name}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (!_loaded) const LinearProgressIndicator(),
        if (_loaded && _items.isNotEmpty)
          AiDraftReview(key: ValueKey(_items.first.uuid),
            draft: _items.first.draft, ledger: widget.ledger,
            people: widget.people.where((person) => !person.isDeleted &&
              widget.ledger.personUuids.contains(person.uuid)).toList(),
            position: _processed + 1, total: _total,
            busy: _busy, onConfirm: _confirm, onSkip: _skip),
        if (_loaded && _items.isEmpty) ...[
          const Text('描述一笔或多笔流水，生成后逐笔复核。'),
          const SizedBox(height: 12),
          TextField(controller: _text, maxLines: 4, maxLength: 1000,
            onChanged: (value) => widget.queue.writeInput(widget.ledger.uuid, value),
            decoration: const InputDecoration(labelText: '描述要记的流水',
              hintText: '例如：早餐18元，午饭32元')),
          const SizedBox(height: 12),
          if (widget.canTranscribe) ...[
            if (_recording) ...[
              FilledButton.tonal(onPressed: _stopAndTranscribe,
                child: const Text('结束录音并转写')),
              TextButton(onPressed: _cancelRecording, child: const Text('取消录音')),
            ] else OutlinedButton.icon(
              onPressed: _voiceBusy ? null : _startRecording,
              icon: const Icon(Icons.mic_none_rounded),
              label: Text(_voiceBusy ? '转写中' : '开始语音输入'),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.canParse)
            FilledButton(onPressed: _busy ? null : _parse, child: const Text('生成草稿'))
          else const Text('当前未获 AI 记账授权，已保存的草稿仍可手动确认。'),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    ));
  }
}
