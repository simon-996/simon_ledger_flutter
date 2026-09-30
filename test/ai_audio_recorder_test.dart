import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/services/ai_audio_recorder.dart';

class FakeRecorderDevice implements AiRecorderDevice {
  FakeRecorderDevice({this.permitted = true, this.failStop = false});
  final bool permitted;
  final bool failStop;
  final chunks = StreamController<Uint8List>.broadcast();
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<Uint8List>> startPcmStream() async {
    starts++;
    return chunks.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('device stopped unexpectedly');
  }

  @override
  Future<void> dispose() async {
    await chunks.close();
  }
}

void main() {
  test('denied microphone permission leaves recording inactive', () async {
    final device = FakeRecorderDevice(permitted: false);
    final recorder = AiAudioRecorder(device: device);
    expect(await recorder.start(), isFalse);
    expect(device.starts, 0);
    await recorder.dispose();
  });

  test('stops PCM stream and returns only in-memory bytes', () async {
    final device = FakeRecorderDevice();
    final recorder = AiAudioRecorder(device: device);
    expect(await recorder.start(), isTrue);
    device.chunks.add(Uint8List.fromList([1, 2, 3, 4]));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(await recorder.stop(), [1, 2, 3, 4]);
    expect(device.stops, 1);
    await recorder.dispose();
  });

  test('clears active state after recorder stop fails', () async {
    final device = FakeRecorderDevice(failStop: true);
    final recorder = AiAudioRecorder(device: device);
    await recorder.start();
    await expectLater(recorder.stop(), throwsStateError);
    expect(recorder.isRecording, isFalse);
    await recorder.dispose();
  });

  test('reports automatic stop failure to the caller', () async {
    final device = FakeRecorderDevice(failStop: true);
    final recorder = AiAudioRecorder(
      device: device,
      maxDuration: const Duration(milliseconds: 10),
    );
    final failure = Completer<void>();
    await recorder.start(onAutoStopError: () => failure.complete());
    await failure.future.timeout(const Duration(seconds: 1));
    expect(recorder.isRecording, isFalse);
    await recorder.dispose();
  });
}
