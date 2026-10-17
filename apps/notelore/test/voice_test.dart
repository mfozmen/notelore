import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/voice.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

void main() {
  Future<(Session, VoiceMode, FakeSpeech, FakeVoice)> setUpVoice(
    List<String?> phrases,
    List<Object> answers, {
    String language = 'en',
  }) async {
    final harness = Harness(answers: answers);
    final session = harness.session(systemLanguage: language);
    await session.connect(findProvider('anthropic'), 'k');
    final speech = FakeSpeech(phrases);
    final voice = FakeVoice();
    return (session, VoiceMode(session, speech: speech, voice: voice), speech, voice);
  }

  test('push to talk: held it listens, let go it sends, and the answer is spoken', () async {
    final (session, mode, speech, voice) = await setUpVoice(
      ['hangi kitabı okuyorum'],
      ['Gülünün Solduğu Akşam.'],
      language: 'tr',
    );
    expect(mode.state, VoiceState.off);
    final talk = mode.press();
    await pumpEventQueue();
    expect(mode.state, VoiceState.listening);
    expect(speech.languages, ['tr']);
    mode.release();
    await talk;
    expect(session.transcript.map((l) => l.text), [
      'hangi kitabı okuyorum',
      'Gülünün Solduğu Akşam.',
    ]);
    expect(voice.spoken, [('Gülünün Solduğu Akşam.', 'tr')]);
    expect(mode.state, VoiceState.off); // waits for the next press, not listening
  });

  test('let go without words: nothing is sent', () async {
    final (session, mode, speech, voice) = await setUpVoice([null], []);
    final talk = mode.press();
    await pumpEventQueue();
    mode.release();
    await talk;
    expect(session.transcript, isEmpty);
    expect(mode.state, VoiceState.off);
    mode.release(); // not listening: nothing happens
    expect(speech.finishes, 1);
  });

  test('a press while the answer is read aloud cuts it short and listens', () async {
    final speaking = Completer<void>();
    final (session, mode, speech, voice) = await setUpVoice(['bir', 'iki'], ['Bir.', 'İki.']);
    voice.holding = speaking;
    final first = mode.press();
    await pumpEventQueue();
    mode.release();
    await pumpEventQueue();
    expect(mode.state, VoiceState.speaking);
    final second = mode.press(); // a new question while it talks
    await pumpEventQueue();
    expect(voice.stops, greaterThan(0));
    expect(mode.state, VoiceState.listening);
    expect(mode.press(), completes); // held already: a second press does nothing
    speaking.complete();
    voice.holding = null;
    mode.release();
    await Future.wait([first, second]);
    expect(session.transcript.map((l) => l.text), ['bir', 'Bir.', 'iki', 'İki.']);
  });

  test('ending while it waits for the answer speaks nothing', () async {
    final answer = Completer<AgentResponse>();
    final (session, mode, speech, voice) = await setUpVoice(['merhaba'], [answer.future]);
    final talk = mode.press();
    await pumpEventQueue();
    mode.release();
    await pumpEventQueue();
    expect(mode.state, VoiceState.thinking);
    mode.end();
    session.stop();
    await talk;
    expect(voice.spoken, isEmpty);
    expect(mode.state, VoiceState.off);
  });

  test('only answers are spoken, without Markdown symbols or suggested answers', () async {
    final (session, mode, speech, voice) = await setUpVoice(
      ['ne var', 've sonra'],
      [
        '**Kitap:** _Gülünün Solduğu Akşam_, [link](https://x.y)\n- `madde`\n# Başlık\n'
            '[[Evet]] [[Hayır]]',
        const NetworkError('offline'),
      ],
    );
    for (var i = 0; i < 2; i++) {
      final talk = mode.press();
      await pumpEventQueue();
      mode.release();
      await talk;
    }
    // The failed second turn (an error line) is not read aloud.
    expect(voice.spoken, [('Kitap: Gülünün Solduğu Akşam, link\nmadde\nBaşlık', 'en')]);
  });

  test('a closed chat ends voice without touching the disposed mode', () async {
    final (session, mode, speech, voice) = await setUpVoice([], []);
    final talk = mode.press();
    await pumpEventQueue();
    mode
      ..end()
      ..dispose();
    await talk; // unwinding after dispose does not throw
    expect(speech.cancels, 1);
  });

  test('no speech recognition: it says so', () async {
    final (session, mode, speech, voice) = await setUpVoice([], []);
    speech.failure = const VoiceUnavailable();
    await mode.press();
    expect(mode.state, VoiceState.off);
    expect(mode.problem, session.strings.voiceUnavailable);
    speech.failure = const ListenFailed('error_network');
    await mode.press();
    expect(mode.problem, session.strings.speechFailed('error_network'));
    speech.failure = Exception('the recognizer crashed');
    await mode.press();
    expect(mode.problem, contains('the recognizer crashed'));
  });

  test('typing quiets the voice', () async {
    final (session, mode, speech, voice) = await setUpVoice([], []);
    mode.hush();
    expect(voice.stops, 1);
  });

  test(
    'letting go reaches the recognizer that is listening, even if Whisper arrived meanwhile',
    () async {
      final harness = Harness()..modelPage = 'whisper bytes';
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'k');
      final mode = VoiceMode(session, voice: harness.voice); // the session's speech
      unawaited(mode.press());
      await pumpEventQueue();
      expect(harness.speech.languages, hasLength(1)); // the device's, listening
      await session.downloadWhisper(); // now the session would pick Whisper
      mode.release();
      await pumpEventQueue();
      expect(harness.speech.finishes, 1);
      expect(harness.whisper.finishes, 0);
    },
  );

  test('a turn overtaken by a new press keeps its failure to itself', () async {
    final speaking = Completer<void>();
    final (session, mode, speech, voice) = await setUpVoice(['bir'], ['Bir.']);
    voice.holding = speaking;
    final first = mode.press();
    await pumpEventQueue();
    mode.release();
    await pumpEventQueue();
    expect(mode.state, VoiceState.speaking);
    voice.holding = null;
    final second = mode.press(); // overtakes the first while it speaks
    await pumpEventQueue();
    speaking.completeError(Exception('the voice broke')); // the first turn fails late
    await first;
    expect(mode.problem, isNull);
    expect(mode.state, VoiceState.listening); // the second turn goes on
    mode.end();
    await second;
  });
}
