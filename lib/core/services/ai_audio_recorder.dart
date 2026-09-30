import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

abstract interface class AiRecorderDevice {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startPcmStream();
  Future<void> stop();
  Future<void> dispose();
}

class PlatformAiRecorderDevice implements AiRecorderDevice {
  PlatformAiRecorderDevice() : _recorder = AudioRecorder();
  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startPcmStream() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

class AiAudioRecorder {
  AiAudioRecorder({
    AiRecorderDevice? device,
    this.maxDuration = const Duration(seconds: 60),
  }) : device = device ?? PlatformAiRecorderDevice();

  static const maxPcmBytes = 60 * 16000 * 2;
  final AiRecorderDevice device;
  final Duration maxDuration;
  final List<int> _buffer = [];
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  bool _active = false;
  bool _stopping = false;
  void Function(Uint8List)? _onAutoStop;
  void Function()? _onAutoStopError;

  bool get isRecording => _active;

  Future<bool> start({
    void Function(Uint8List)? onAutoStop,
    void Function()? onAutoStopError,
  }) async {
    if (_active) return true;
    if (!await device.hasPermission()) return false;
    _buffer.clear();
    _onAutoStop = onAutoStop;
    _onAutoStopError = onAutoStopError;
    final stream = await device.startPcmStream();
    _active = true;
    _subscription = stream.listen((chunk) {
      if (!_active) return;
      if (_buffer.length + chunk.length > maxPcmBytes) {
        unawaited(_autoStop());
        return;
      }
      _buffer.addAll(chunk);
    });
    _timer = Timer(maxDuration, () => unawaited(_autoStop()));
    return true;
  }

  Future<void> _autoStop() async {
    if (!_active || _stopping) return;
    final onAutoStop = _onAutoStop;
    final onAutoStopError = _onAutoStopError;
    try {
      final bytes = await stop();
      onAutoStop?.call(bytes);
    } catch (_) {
      onAutoStopError?.call();
    }
  }

  Future<Uint8List> stop() async {
    if (!_active || _stopping) return Uint8List(0);
    _stopping = true;
    _timer?.cancel();
    try {
      await _subscription?.cancel();
      await device.stop();
      final bytes = Uint8List.fromList(_buffer);
      return bytes;
    } finally {
      _buffer.clear();
      _active = false;
      _stopping = false;
      _subscription = null;
      _onAutoStop = null;
      _onAutoStopError = null;
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    try {
      if (_active) await stop();
    } finally {
      _buffer.clear();
      await device.dispose();
    }
  }
}
