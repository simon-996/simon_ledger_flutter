import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/repositories/ai_bookkeeping_repository.dart';
import '../../../../core/services/ai_draft_queue.dart';
import '../../../../core/services/ai_draft_identity_mapper.dart';
import '../../../../core/preferences/transaction_category_preference.dart';
import '../../../../core/services/ai_audio_recorder.dart';
import 'ai_draft_review.dart';

bool isAiBookkeepingEligible(Ledger ledger, bool signedIn) =>
    signedIn && ledger.isCloudManaged && ledger.canRecordTransactions;

String currentAiTimeZone() {
  final offset = DateTime.now().timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '$sign${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

String aiBookkeepingErrorMessage(Object error, {String fallback = '操作失败'}) {
  if (error is ApiException &&
      error.code == 403001 &&
      error.message.contains('次数')) {
    return '今日 AI 记账次数已用完';
  }
  return FriendlyError.message(error, fallback: fallback);
}

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
  bool _busy = false;
  bool _loaded = false;
  bool _restoreFailed = false;
  String? _error;
  late final AiAudioRecorder _recorder;
  bool _recording = false;
  bool _voiceBusy = false;
  int _recordingSeconds = 0;
  Timer? _recordingTicker;
  Future<void> _pendingEdit = Future<void>.value();
  bool _editSaveFailed = false;
  int _editRevision = 0;
  Future<void> _pendingInput = Future<void>.value();
  bool _inputSaveFailed = false;
  int _inputRevision = 0;
  bool _closing = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? AiAudioRecorder();
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _restoreFailed = false;
      _error = null;
    });
    try {
      final text = await widget.queue.readInput(widget.ledger.uuid);
      final items = await widget.queue.load(widget.ledger.uuid);
      final restored = <AiDraftItem>[];
      for (final item in items) {
        final draft = normalizeAiDraftPeople(item.draft, _activePeople);
        if (jsonEncode(draft.toJson()) != jsonEncode(item.draft.toJson())) {
          await widget.queue.update(
            widget.ledger.uuid,
            item.uuid,
            draft,
            amountInput: item.amountInput,
          );
        }
        restored.add(item.withDraft(draft));
      }
      if (!mounted) return;
      _text.text = text;
      setState(() {
        _items = restored;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _restoreFailed = true;
        _error = '草稿恢复失败，请重试；原草稿未删除';
      });
    }
  }

  List<Person> get _activePeople => widget.people
      .where(
        (person) =>
            !person.isDeleted &&
            widget.ledger.personUuids.contains(person.uuid),
      )
      .toList();

  Future<bool> _confirmDisclosure() async {
    final prefs = await SharedPreferences.getInstance();
    final key =
        'ai_bookkeeping_disclosure.v2.${widget.queue.scope.storageKey}.text';
    if (prefs.getBool(key) == true) return true;
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用 AI 记账'),
        content: const Text(
          '你的记账描述、当前账本人员姓名和现有分类名称会发送给第三方 AI 服务解析。系统只生成草稿；请核对金额、人员和分类后逐笔确认。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    await prefs.setBool(key, true);
    return true;
  }

  Future<void> _startRecording() async {
    if (_busy || _voiceBusy || _recording || !widget.canTranscribe) return;
    try {
      final allowed = await _recorder.start(
        onAutoStop: (bytes) {
          if (!mounted) {
            bytes.fillRange(0, bytes.length, 0);
            return;
          }
          _stopRecordingTicker();
          setState(() => _recording = false);
          unawaited(_upload(bytes));
        },
        onAutoStopError: () {
          _stopRecordingTicker();
          if (mounted) {
            setState(() {
              _recording = false;
              _error = '录音结束失败，可继续使用文字输入';
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _recording = allowed;
        _recordingSeconds = 0;
        _error = allowed ? null : '未获得麦克风权限，可继续使用文字输入';
      });
      if (allowed) {
        _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && _recording) setState(() => _recordingSeconds++);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法开始录音，可继续使用文字输入');
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (!_recording || _voiceBusy) return;
    _stopRecordingTicker();
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
    _stopRecordingTicker();
    try {
      final bytes = await _recorder.stop();
      bytes.fillRange(0, bytes.length, 0);
    } catch (_) {
      if (mounted) setState(() => _error = '取消录音失败，可继续使用文字输入');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  void _stopRecordingTicker() {
    _recordingTicker?.cancel();
    _recordingTicker = null;
  }

  Future<void> _upload(Uint8List bytes) async {
    if (_voiceBusy) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    if (bytes.isEmpty) {
      if (mounted) setState(() => _error = '录音为空，请重试');
      return;
    }
    if (mounted) {
      setState(() {
        _voiceBusy = true;
        _error = null;
      });
    }
    try {
      final transcript = await widget.repository.transcribe(
        widget.ledger.remoteSyncUuid,
        bytes,
      );
      if (!mounted) return;
      var nextText = transcript;
      final currentText = _text.text.trim();
      if (currentText.isNotEmpty && currentText != transcript.trim()) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('替换已有文字？'),
            content: const Text('语音已转成文字。你可以替换、追加，或保留当前输入。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'keep'),
                child: const Text('保留原文'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'append'),
                child: const Text('追加转写'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'replace'),
                child: const Text('使用转写'),
              ),
            ],
          ),
        );
        if (choice == 'keep' || choice == null || !mounted) return;
        if (choice == 'append') nextText = '$currentText\n$transcript';
      }
      _text.text = nextText;
      await _persistInput(nextText);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '${aiBookkeepingErrorMessage(error, fallback: '语音转写失败')}；可继续使用文字输入',
        );
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _parse() async {
    if (_busy || _voiceBusy || _recording || !widget.canParse) return;
    final input = _text.text.trim();
    if (input.isEmpty || input.runes.length > 1000) {
      setState(() => _error = '请输入 1 到 1000 字的记账描述');
      return;
    }
    if (!await _confirmDisclosure()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _persistInput(input);
      if (_inputSaveFailed) {
        if (mounted) setState(() => _error = '文字输入暂未保存，请重试生成草稿');
        return;
      }
      final categories = await TransactionCategoryPreference.read();
      final drafts = await widget.repository.parse(
        widget.ledger.remoteSyncUuid,
        input,
        currentAiTimeZone(),
        expenseCategories: categories.expense,
        incomeCategories: categories.income,
      );
      final items = await widget.queue.add(
        widget.ledger.uuid,
        drafts
            .map((draft) => normalizeAiDraftPeople(draft, _activePeople))
            .toList(),
      );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _items = items;
      });
      try {
        await _persistInput('');
        if (_inputSaveFailed) throw StateError('输入记录清理失败');
      } catch (_) {
        if (mounted) {
          setState(() => _error = '草稿已生成，但输入记录清理失败；下次进入可能显示旧描述');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '${aiBookkeepingErrorMessage(error, fallback: '解析失败')}；输入已保留',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(AiDraft draft) async {
    if (_busy || _items.isEmpty) return;
    final item = _items.first;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _pendingEdit;
      if (_editSaveFailed) throw StateError('草稿修改未保存');
      if (!await widget.queue.isSaved(widget.ledger.uuid, item)) {
        await widget.onSave(item, draft);
      }
      await widget.queue.remove(widget.ledger.uuid, item.uuid);
      final remaining = await widget.queue.load(widget.ledger.uuid);
      if (!mounted) return;
      setState(() {
        _items = remaining;
      });
    } catch (error) {
      var saved = false;
      try {
        saved = await widget.queue.isSaved(widget.ledger.uuid, item);
      } catch (_) {
        // Keep the draft visible when local lookup is also unavailable.
      }
      if (mounted) {
        setState(
          () => _error = saved
              ? '流水已保存，草稿整理失败；重试会先核对已保存流水'
              : '${aiBookkeepingErrorMessage(error, fallback: '保存失败')}；草稿已保留',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    if (_busy || _items.isEmpty) return;
    final skip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确定跳过这笔草稿？'),
        content: const Text('跳过后这笔草稿会从待确认列表移除，不会记账。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续复核'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定跳过'),
          ),
        ],
      ),
    );
    if (skip != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _pendingEdit;
      final item = _items.first;
      await widget.queue.remove(widget.ledger.uuid, item.uuid);
      final remaining = await widget.queue.load(widget.ledger.uuid);
      if (!mounted) return;
      setState(() {
        _items = remaining;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '跳过失败，草稿仍保留，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestClose() async {
    if (_closing || _busy || _voiceBusy) return;
    _closing = true;
    try {
      if (_recording) await _cancelRecording();
      await _pendingEdit;
      await _pendingInput;
      if (_editSaveFailed) {
        if (mounted) setState(() => _error = '修改暂未保存，请重试后再关闭');
        return;
      }
      if (_inputSaveFailed) {
        if (mounted) setState(() => _error = '文字输入暂未保存，请修改后重试关闭');
        return;
      }
      if (mounted) {
        setState(() => _allowPop = true);
        Navigator.of(context).pop();
      }
    } finally {
      _closing = false;
    }
  }

  void _editDraft(AiDraft draft, String amountInput) {
    if (_items.isEmpty) return;
    final item = _items.first;
    final revision = ++_editRevision;
    setState(() {
      _items[0] = item.withDraft(draft, amountInput: amountInput);
      _editSaveFailed = false;
    });
    _pendingEdit = _pendingEdit
        .then(
          (_) => widget.queue.update(
            widget.ledger.uuid,
            item.uuid,
            draft,
            amountInput: amountInput,
          ),
        )
        .then(
          (_) {
            if (revision != _editRevision) return;
            _editSaveFailed = false;
            if (mounted) setState(() => _error = null);
          },
          onError: (Object _) {
            if (revision != _editRevision) return;
            _editSaveFailed = true;
            if (mounted) {
              setState(() => _error = '修改暂未保存，请重试编辑或保持页面开启');
            }
          },
        );
  }

  Future<void> _persistInput(String value) {
    final revision = ++_inputRevision;
    _pendingInput = _pendingInput
        .then((_) => widget.queue.writeInput(widget.ledger.uuid, value))
        .then(
          (_) {
            if (revision != _inputRevision) return;
            _inputSaveFailed = false;
          },
          onError: (Object _) {
            if (revision != _inputRevision) return;
            _inputSaveFailed = true;
            if (mounted) setState(() => _error = '文字输入暂未保存，请修改后重试');
          },
        );
    return _pendingInput;
  }

  @override
  void dispose() {
    _stopRecordingTicker();
    _text.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'AI 记账 · ${widget.ledger.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭 AI 记账',
                    onPressed: _busy || _voiceBusy ? null : _requestClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_loaded)
              Expanded(
                child: Center(
                  child: _restoreFailed
                      ? OutlinedButton(
                          onPressed: _restore,
                          child: const Text('重试恢复草稿'),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            if (_loaded && _items.isNotEmpty)
              Expanded(
                child: AiDraftReview(
                  key: ValueKey(_items.first.uuid),
                  draft: _items.first.draft,
                  ledger: widget.ledger,
                  amountInput: _items.first.amountInput,
                  people: _activePeople,
                  position: _items.first.position,
                  total: _items.first.total,
                  busy: _busy,
                  onConfirm: _confirm,
                  onSkip: _skip,
                  onChanged: _editDraft,
                ),
              ),
            if (_loaded && _items.isEmpty)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('描述一笔或多笔流水，生成后逐笔复核。'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _text,
                        enabled: !_busy,
                        maxLines: 4,
                        maxLength: 1000,
                        onChanged: _persistInput,
                        decoration: const InputDecoration(
                          labelText: '描述要记的流水',
                          hintText:
                              '例如：张三吃早餐花了20元，所有人一起坐地铁花了30泰铢，所有人吃零食花了80元，李四垫付的',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.canTranscribe) ...[
                        if (_recording) ...[
                          Text(
                            '录音中 ${(_recordingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_recordingSeconds % 60).toString().padLeft(2, '0')} / 01:00',
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: _stopAndTranscribe,
                            child: const Text('结束录音并转写'),
                          ),
                          TextButton(
                            onPressed: _cancelRecording,
                            child: const Text('取消录音'),
                          ),
                        ] else
                          OutlinedButton.icon(
                            onPressed: _voiceBusy || _busy
                                ? null
                                : _startRecording,
                            icon: const Icon(Icons.mic_none_rounded),
                            label: Text(_voiceBusy ? '转写中' : '开始语音输入'),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.canParse)
                        FilledButton(
                          onPressed: _busy || _voiceBusy || _recording
                              ? null
                              : _parse,
                          child: Text(_busy ? '解析中…' : '生成草稿'),
                        )
                      else
                        const Text('当前未获 AI 记账授权，已保存的草稿仍可手动确认。'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
