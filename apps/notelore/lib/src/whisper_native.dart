/// The device side of on-device speech: the microphone (record), the Silero
/// voice-activity detector and Whisper (sherpa-onnx, native code over FFI).
///
/// These run only on a device: `flutter test` cannot load the native
/// libraries, so the bodies are left out of the coverage gate, and kept thin.
/// The logic around them lives in `whisper_speech.dart`, fully tested.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice.dart';
import 'whisper_model.dart';
import 'whisper_speech.dart';

// coverage:ignore-start
const _rate = 16000;

/// Whisper speech over a downloaded [model].
Speech nativeWhisper(WhisperModel model, String? Function() device) => WhisperSpeech(
  microphone: RecordMicrophone(device),
  detector: SileroDetector(model),
  transcriber: IsolateTranscriber(model),
);

/// The microphone as 16 kHz mono PCM.
/// The microphones the device lists.
Future<List<MicrophoneChoice>> nativeMicrophones() async {
  final recorder = AudioRecorder();
  try {
    return [for (final d in await recorder.listInputDevices()) (id: d.id, label: d.label)];
  } on Exception {
    return const []; // none listed: the system default only
  } finally {
    unawaited(recorder.dispose());
  }
}

class RecordMicrophone implements Microphone {
  RecordMicrophone(this.device);

  /// The chosen microphone's id, asked at every start; null is the default.
  final String? Function() device;
  final _recorder = AudioRecorder();

  @override
  Future<Stream<Uint8List>> start() async {
    if (!await _recorder.hasPermission()) throw const VoiceUnavailable();
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _rate,
        numChannels: 1,
        device: switch (device()) {
          final String id => InputDevice(id: id, label: id),
          null => null,
        },
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }
}

/// Silero VAD: a phrase ends after 0.8 s of silence (or 30 s of speech).
class SileroDetector implements PhraseDetector {
  SileroDetector(this.model);

  final WhisperModel model;
  sherpa.VoiceActivityDetector? _vad;

  @override
  int get window => 512; // what Silero takes per call

  @override
  Float32List? accept(Float32List samples) {
    if (_vad == null) sherpa.initBindings(); // once per isolate; the transcriber has its own
    final vad = _vad ??= sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: model.path('silero_vad.onnx'),
          minSilenceDuration: 0.8,
          maxSpeechDuration: 30,
        ),
        sampleRate: _rate,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
    vad.acceptWaveform(samples);
    if (vad.isEmpty()) return null;
    final phrase = vad.front().samples;
    vad.pop();
    return phrase;
  }

  @override
  bool get speaking => _vad?.isDetected() ?? false;

  @override
  void reset() => _vad?.reset();
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
