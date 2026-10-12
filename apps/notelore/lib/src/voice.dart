/// Voice: hold to talk, the assistant answers aloud, typing still works.
///
/// Whisper or the device does the listening, the device the speaking ([Speech],
/// [Voice]): free, no extra API. [VoiceMode] runs one turn per press.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// Listens while the button is held: push to talk.
abstract interface class Speech {
  /// What was said in [language] (`en`, `tr`) by the time of [finish], or null
  /// for silence or a [cancel]. Throws [VoiceUnavailable] or [ListenFailed].
  Future<String?> listen(String language);

  /// The button is let go: what was said so far is the phrase.
  Future<void> finish();

  /// Drops what was said.
  Future<void> cancel();
}

/// Reads text aloud.
abstract interface class Voice {
  /// Completes when the text has been spoken or [stop]ped.
  Future<void> speak(String text, String language);

  Future<void> stop();
}

enum VoiceState { off, listening, thinking, speaking }

/// Push to talk: held, it listens; let go, what was said is sent and the
/// answer read aloud. Typing works as ever.
class VoiceMode extends ChangeNotifier {
  VoiceMode(this.session, {this._speech, required this.voice});

  final Session session;
  final Speech? _speech;

  /// The session's, by default: Whisper or the device's, as Settings has it now.
  Speech get speech => _speech ?? session.speech;

  /// The recognizer of the listen under way: Whisper may arrive meanwhile, and
  /// a let-go must reach the one that is listening.
  Speech? _listening;
  final Voice voice;

  VoiceState state = VoiceState.off;

  /// Why the last press failed, if it did.
  String? problem;

  /// Each press is a turn; one that was ended or overtaken changes nothing.
  var _turn = 0;

  /// The button went down: listen until [release]. A press while the answer is
  /// read aloud cuts it short. Completes when the turn is over.
  Future<void> press() async {
    if (state case VoiceState.listening || VoiceState.thinking) return;
    final turn = ++_turn;
    problem = null;
    String? failed;
    unawaited(voice.stop());
    _set(VoiceState.listening);
    try {
      final ears = _listening = speech;
      final text = await ears.listen(session.strings.languageCode);
      if (turn != _turn) return;
      if (text == null || text.trim().isEmpty) return _set(VoiceState.off);
      _set(VoiceState.thinking);
      await session.send(text);
      if (turn != _turn) return;
      final last = session.transcript.last;
      if (last.role == ChatRole.assistant) {
        _set(VoiceState.speaking);
        await voice.speak(spoken(last.text), session.strings.languageCode);
      } // an error stays on screen, unspoken
    } on VoiceUnavailable {
      failed = session.strings.voiceUnavailable;
    } on ListenFailed catch (error) {
      failed = session.strings.speechFailed(error.message);
    } on Exception catch (error) {
      failed = '$error';
    }
    if (turn != _turn) return; // ended or overtaken: its failure is its own
    problem = failed;
    _set(VoiceState.off);
  }

  /// The button came up: what was said is the phrase.
  void release() {
    if (state == VoiceState.listening) unawaited((_listening ?? speech).finish());
  }

  /// Typing began: the voice stops talking.
  void hush() => unawaited(voice.stop());

  /// Drops what is under way: the listening, the waiting, the voice.
  void end() {
    _turn++;
    _set(VoiceState.off);
    unawaited((_listening ?? speech).cancel());
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

  /// The latest words heard in this listening, final or not.
  var _latest = '';

  // Silence, not a failure: nothing was said, or nothing understood.
  static const _silence = {'error_no_match', 'error_speech_timeout'};

  @override
  Future<String?> listen(String language) async {
    try {
      _ready =
          _ready ||
          await _recognizer.initialize(
            onStatus: _status,
            onError: (error) {
              _trace('error ${error.errorMsg} (permanent: ${error.permanent})');
              _silence.contains(error.errorMsg)
                  ? _end(_latest.isEmpty ? null : _latest)
                  : _fail(ListenFailed(error.errorMsg));
            },
            // Only the microphone: the headset setup would ask for Bluetooth too.
            options: [SpeechToText.androidNoBluetooth],
          );
    } on PlatformException catch (error) {
      // Android: no speech service on the device (or none the app may use).
      if (error.code == 'recognizerNotAvailable') throw const VoiceUnavailable();
      throw ListenFailed(error.message ?? error.code);
    }
    if (!_ready) throw const VoiceUnavailable();
    final heard = _heard = Completer<String?>();
    _latest = '';
    _trace('listening ($language)');
    await _recognizer.listen(
      onResult: (result) {
        _trace('result ${result.resultTypeValue.name}, ${result.recognizedWords.length} chars');
        if (result.recognizedWords.isNotEmpty) _latest = result.recognizedWords;
        if (result.finalResult) _end(result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: language == 'tr' ? 'tr_TR' : 'en_US',
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 30), // held: a pause does not end it
        listenFor: const Duration(minutes: 1),
      ),
    );
    return heard.future;
  }

  void _status(String status) {
    _trace('status $status');
    // Some recognizers (Windows, some Android) never mark their last words
    // final: when listening is done, what was heard last is the phrase.
    if (status == SpeechToText.doneStatus) _end(_latest.isEmpty ? null : _latest);
  }

  void _end(String? words) {
    if (_heard case final heard? when !heard.isCompleted) heard.complete(words);
  }

  void _fail(ListenFailed error) {
    if (_heard case final heard? when !heard.isCompleted) heard.completeError(error);
  }

  @override
  Future<void> finish() async {
    _trace('finish');
    await _recognizer.stop();
    _end(_latest.isEmpty ? null : _latest);
  }

  @override
  Future<void> cancel() async {
    _trace('cancel');
    _end(null);
    await _recognizer.cancel();
  }
}

/// One line per voice step in the device log (logcat, the console): how a
/// recognizer behaves on a given device can only be seen there.
void _trace(String step) => debugPrint('notelore voice: $step');

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
