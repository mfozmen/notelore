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

  test('starts off; a heard phrase is sent, the answer spoken, then it listens again', () async {
    final (session, mode, speech, voice) = await setUpVoice(
      ['hangi kitabı okuyorum', null, 'teşekkürler'],
      ['Gülünün Solduğu Akşam.', 'Rica ederim.'],
      language: 'tr',
    );
    expect(mode.state, VoiceState.off);
    final running = mode.start();
    await pumpEventQueue();
    expect(mode.state, VoiceState.listening); // silence was skipped, still listening
    expect(voice.spoken, [('Gülünün Solduğu Akşam.', 'tr'), ('Rica ederim.', 'tr')]);
    expect(session.transcript.map((l) => l.text), [
      'hangi kitabı okuyorum',
      'Gülünün Solduğu Akşam.',
      'teşekkürler',
      'Rica ederim.',
    ]);
    expect(speech.languages.toSet(), {'tr'});
    mode.end();
    await running;
    expect(mode.state, VoiceState.off);
    expect(speech.cancels, greaterThan(0));
    expect(voice.stops, greaterThan(0));
  });

  test('a typed message in voice mode is sent and answered aloud', () async {
    final (session, mode, speech, voice) = await setUpVoice([], ['Yazdın.']);
    final running = mode.start();
    await pumpEventQueue();
    mode.hush(); // typing began: the voice stops
    expect(voice.stops, 1);
    mode.type('selam');
    await pumpEventQueue();
    expect(session.transcript.first.text, 'selam');
    expect(voice.spoken, [('Yazdın.', 'en')]);
    expect(mode.state, VoiceState.listening);
    mode.end();
    await running;
  });

  test('ending while it waits for the answer speaks nothing', () async {
    final answer = Completer<AgentResponse>();
    final (session, mode, speech, voice) = await setUpVoice(['merhaba'], [answer.future]);
    final running = mode.start();
    await pumpEventQueue();
    expect(mode.state, VoiceState.thinking);
    mode.end();
    session.stop();
    await running;
    expect(voice.spoken, isEmpty);
    expect(mode.start(), completes); // it can start again
    mode.end();
  });

  test('only answers are spoken, without Markdown symbols', () async {
    final (session, mode, speech, voice) = await setUpVoice(
      ['ne var', 've sonra'],
      [
        '**Kitap:** _Gülünün Solduğu Akşam_, [link](https://x.y)\n- `madde`\n# Başlık',
        const NetworkError('offline'),
      ],
    );
    final running = mode.start();
    await pumpEventQueue();
    // The failed second turn (an error line) is not read aloud.
    expect(voice.spoken, [('Kitap: Gülünün Solduğu Akşam, link\nmadde\nBaşlık', 'en')]);
    mode.end();
    await running;
  });

  test('a closed chat ends voice mode without touching the disposed mode', () async {
    final (session, mode, speech, voice) = await setUpVoice([], []);
    final running = mode.start();
    await pumpEventQueue();
    mode
      ..end()
      ..dispose();
    await running; // unwinding after dispose does not throw
  });

  test('no speech recognition: it says so and stays in text mode', () async {
    final (session, mode, speech, voice) = await setUpVoice([], []);
    speech.failure = const VoiceUnavailable();
    await mode.start();
    expect(mode.state, VoiceState.off);
    expect(mode.problem, session.strings.voiceUnavailable);
    speech.failure = const ListenFailed('error_network');
    await mode.start();
    expect(mode.problem, session.strings.speechFailed('error_network'));
    speech.failure = Exception('the recognizer crashed');
    await mode.start();
    expect(mode.problem, contains('the recognizer crashed'));
    expect(mode.start, returnsNormally);
    mode.end();
  });
}
