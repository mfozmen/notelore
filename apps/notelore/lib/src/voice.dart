/// Voice mode: the user talks, the assistant answers aloud, typing still works.
///
/// The device does the listening and the speaking ([Speech], [Voice]): free,
/// no extra API. [VoiceMode] runs the loop: listen for one phrase, send it,
/// speak the answer, listen again, until [VoiceMode.end].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'session.dart';

/// Speech recognition is not available: no permission, no recognizer, or (on
/// Windows) no speech pack for the language.
class VoiceUnavailable implements Exception {
  const VoiceUnavailable();
}

/// The recognizer failed for a reason other than silence (network, busy).
class ListenFailed implements Exception {
  const ListenFailed(this.message);

  final String message;

  @override
  String toString() => 'Speech recognition failed: $message';
}

/// [markdown] as plain words for a voice: no emphasis marks, list bullets,
/// heading marks or link targets.
String spoken(String markdown) => markdown
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'^\s*(#+|[-*+])\s+', multiLine: true), '')
    .replaceAll(RegExp(r'[*_`]'), '');

/// Listens for one phrase.
abstract interface class Speech {
  /// The phrase heard in [language] (`en`, `tr`), or null for silence or a
  /// [cancel]. Throws [VoiceUnavailable] or [ListenFailed].
  Future<String?> listen(String language);

  Future<void> cancel();
}

/// Reads text aloud.
abstract interface class Voice {
  /// Completes when the text has been spoken or [stop]ped.
  Future<void> speak(String text, String language);

  Future<void> stop();
}

enum VoiceState { off, listening, thinking, speaking }

class VoiceMode extends ChangeNotifier {
  VoiceMode(this.session, {required this.speech, required this.voice});

  final Session session;
  final Speech speech;
  final Voice voice;

  VoiceState state = VoiceState.off;

  /// Why the last start ended in text mode, if it failed.
  String? problem;

  /// A message typed while listening; it is sent instead of what is heard.
  String? _typed;

  bool get on => state != VoiceState.off;

  /// Listens and answers aloud until [end]; completes once back in text mode.
  Future<void> start() async {
    if (on) return;
    problem = null;
    _set(VoiceState.listening);
    try {
      await _loop();
    } on VoiceUnavailable {
      problem = session.strings.voiceUnavailable;
    } on ListenFailed catch (error) {
      problem = session.strings.speechFailed(error.message);
    } on Exception catch (error) {
      problem = '$error';
    }
    _set(VoiceState.off);
  }

  Future<void> _loop() async {
    while (on) {
      var text = _typed;
      _typed = null;
      if (text == null) {
        _set(VoiceState.listening);
        text = await speech.listen(session.strings.languageCode) ?? _typed;
        _typed = null;
      }
      if (!on) return;
      if (text == null || text.trim().isEmpty) continue; // silence: listen again
      _set(VoiceState.thinking);
      await session.send(text);
      if (!on) return;
      final last = session.transcript.last;
      if (last.role != ChatRole.assistant) continue; // an error stays on screen, unspoken
      _set(VoiceState.speaking);
      await voice.speak(spoken(last.text), session.strings.languageCode);
    }
  }

  /// Typing began: the voice stops talking.
  void hush() => unawaited(voice.stop());

  /// A typed message: sent in place of listening, and answered aloud.
  void type(String text) {
    _typed = text;
    unawaited(speech.cancel());
    unawaited(voice.stop());
  }

  /// Back to text mode.
  void end() {
    _set(VoiceState.off);
    unawaited(speech.cancel());
    unawaited(voice.stop());
  }

  var _disposed = false;

  /// The chat may close mid-loop: the loop then unwinds without notifying.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _set(VoiceState next) {
    state = next;
    if (!_disposed) notifyListeners();
  }
}

/// The device's speech recognition (speech_to_text).
class DeviceSpeech implements Speech {
  DeviceSpeech([SpeechToText? recognizer]) : _recognizer = recognizer ?? SpeechToText();

  final SpeechToText _recognizer;
  var _ready = false;
  Completer<String?>? _heard;

  // Silence, not a failure: nothing was said, or nothing understood.
  static const _silence = {'error_no_match', 'error_speech_timeout'};

  @override
  Future<String?> listen(String language) async {
    _ready =
        _ready ||
        await _recognizer.initialize(
          onStatus: _status,
          onError: (error) =>
              _silence.contains(error.errorMsg) ? _end(null) : _fail(ListenFailed(error.errorMsg)),
        );
    if (!_ready) throw const VoiceUnavailable();
    final heard = _heard = Completer<String?>();
    await _recognizer.listen(
      onResult: (result) {
        if (result.finalResult) _end(result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: language == 'tr' ? 'tr_TR' : 'en_US',
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 3), // a pause ends the phrase
        listenFor: const Duration(minutes: 1),
      ),
    );
    return heard.future;
  }

  void _status(String status) {
    if (status == SpeechToText.doneStatus) _end(null); // done without a phrase
  }

  void _end(String? words) {
    if (_heard case final heard? when !heard.isCompleted) heard.complete(words);
  }

  void _fail(ListenFailed error) {
    if (_heard case final heard? when !heard.isCompleted) heard.completeError(error);
  }

  @override
  Future<void> cancel() async {
    _end(null);
    await _recognizer.cancel();
  }
}

/// The device's voices (flutter_tts).
class DeviceVoice implements Voice {
  DeviceVoice([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> speak(String text, String language) async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(language == 'tr' ? 'tr-TR' : 'en-US');
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async => _tts.stop();
}
