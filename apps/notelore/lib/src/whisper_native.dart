/// The device side of on-device speech: the microphone (record) and Whisper
/// (sherpa-onnx, native code over FFI).
///
/// These run only on a device: `flutter test` cannot load the native
/// libraries, so the bodies are left out of the coverage gate, and kept thin.
/// The logic around them lives in `whisper_speech.dart`, fully tested.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice.dart';
import 'whisper_model.dart';
import 'whisper_speech.dart';

// coverage:ignore-start
const _rate = 16000;

/// Whisper speech over a downloaded [model].
Speech nativeWhisper(WhisperModel model, String? Function() device) =>
    WhisperSpeech(microphone: RecordMicrophone(device), transcriber: IsolateTranscriber(model));

/// Whisper over a downloaded [model], for attached audio files (#285).
Transcriber nativeTranscriber(WhisperModel model) => IsolateTranscriber(model);

/// The microphones the device lists.
Future<List<MicrophoneChoice>> nativeMicrophones() async {
  final recorder = AudioRecorder();
  try {
    return [for (final d in await recorder.listInputDevices()) (id: d.id, label: d.label)];
  } on Exception catch (error) {
    debugPrint('notelore voice: no microphones listed: $error');
    return const []; // none listed: the system default only
  } finally {
    unawaited(recorder.dispose());
  }
}

/// The microphone as 16 kHz mono PCM.
class RecordMicrophone implements Microphone {
  RecordMicrophone(this.device);

  /// The chosen microphone's id, asked at every start; null is the default.
  final String? Function() device;
  final _recorder = AudioRecorder();

  @override
  Future<Stream<Uint8List>> start() async {
    if (!await _recorder.hasPermission()) throw const VoiceUnavailable();
    final id = device();
    // One picked earlier but not plugged in now: the default instead.
    final present = id != null && (await nativeMicrophones()).any((m) => m.id == id);
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _rate,
        numChannels: 1,
        device: present ? InputDevice(id: id, label: id) : null,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }
}

/// Whisper in a background isolate, so the screen never waits on it. The
/// model loads once per language and stays loaded.
class IsolateTranscriber implements Transcriber {
  IsolateTranscriber(this.model);

  final WhisperModel model;
  Future<SendPort>? _worker;

  @override
  Future<String> transcribe(Float32List samples, String language) async {
    final worker = await (_worker ??= _start(model.dir));
    final reply = ReceivePort();
    worker.send((samples, language, reply.sendPort));
    final (ok, text) = await reply.first as (bool, String);
    reply.close();
    if (!ok) throw ListenFailed(text);
    return text;
  }
}

Future<SendPort> _start(String dir) async {
  final ready = ReceivePort();
  await Isolate.spawn(_work, (ready.sendPort, dir));
  return await ready.first as SendPort;
}

void _work((SendPort, String) start) {
  final (ready, dir) = start;
  sherpa.initBindings();
  final model = WhisperModel(dir);
  final recognizers = <String, sherpa.OfflineRecognizer>{};
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  inbox.listen((message) {
    final (samples, language, reply) = message as (Float32List, String, SendPort);
    try {
      final recognizer = recognizers[language] ??= sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: model.path('small-encoder.int8.onnx'),
              decoder: model.path('small-decoder.int8.onnx'),
              language: language,
              task: 'transcribe',
            ),
            tokens: model.path('small-tokens.txt'),
            numThreads: 4,
            debug: false,
          ),
        ),
      );
      final stream = recognizer.createStream()..acceptWaveform(samples: samples, sampleRate: _rate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      stream.free();
      reply.send((true, text));
    } on Object catch (error) {
      reply.send((false, '$error'));
    }
  });
}
// coverage:ignore-end
