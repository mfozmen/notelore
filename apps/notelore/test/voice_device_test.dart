import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:notelore/src/voice.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// The platform side of speech_to_text, driven by the test.
class FakeRecognizer extends SpeechToTextPlatform with MockPlatformInterfaceMixin {
  var available = true;
  final asked = <String?>[];
  var cancels = 0;

  @override
  Future<bool> initialize({debugLogging = false, List<SpeechConfigOption>? options}) async =>
      available;

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    asked.add(options?.localeId ?? localeId);
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async => cancels++;

  void hear(String words) => onTextRecognition!(
    jsonEncode({
      'alternates': [
        {'recognizedWords': words, 'confidence': 0.9},
      ],
      'resultType': 2, // final
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRecognizer platform;
  late DeviceSpeech speech;
  setUp(() {
    platform = FakeRecognizer();
    SpeechToTextPlatform.instance = platform;
    speech = DeviceSpeech(SpeechToText.withMethodChannel());
  });

  test('a phrase heard in the app language', () async {
    final heard = speech.listen('tr');
    await pumpEventQueue();
    platform.hear('hangi kitabı okuyorum');
    expect(await heard, 'hangi kitabı okuyorum');
    expect(platform.asked, ['tr_TR']);
    final english = speech.listen('en');
    await pumpEventQueue();
    platform.hear('hello');
    expect(await english, 'hello');
    expect(platform.asked.last, 'en_US');
  });

  test('silence, an error and a cancel end the listening without a phrase', () async {
    final silent = speech.listen('en');
    await pumpEventQueue();
    platform.onStatus!('doneNoResult');
    expect(await silent, isNull);
    final failed = speech.listen('en');
    await pumpEventQueue();
    platform.onError!(jsonEncode({'errorMsg': 'error_no_match', 'permanent': false}));
    expect(await failed, isNull);
    final timedOut = speech.listen('en');
    await pumpEventQueue();
    platform.onError!(jsonEncode({'errorMsg': 'error_speech_timeout', 'permanent': false}));
    expect(await timedOut, isNull);
    final cancelled = speech.listen('en');
    await pumpEventQueue();
    await speech.cancel();
    expect(await cancelled, isNull);
    expect(platform.cancels, 1);
  });

  test('a real recognizer error ends the listening with that error', () async {
    final broken = speech.listen('en');
    await pumpEventQueue();
    platform.onError!(jsonEncode({'errorMsg': 'error_network', 'permanent': true}));
    await expectLater(
      broken,
      throwsA(isA<ListenFailed>().having((e) => '$e', 'text', contains('error_network'))),
    );
  });

  test('no recognizer or no permission: unavailable', () async {
    platform.available = false;
    await expectLater(speech.listen('en'), throwsA(isA<VoiceUnavailable>()));
  });

  test('the device voice speaks in the app language and stops', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async {
        calls.add(call);
        return 1;
      },
    );
    final voice = DeviceVoice(FlutterTts());
    await voice.speak('Merhaba', 'tr');
    await voice.speak('Hello', 'en');
    await voice.stop();
    expect(calls.map((c) => (c.method, c.arguments)), [
      ('awaitSpeakCompletion', true),
      ('setLanguage', 'tr-TR'),
      ('speak', 'Merhaba'),
      ('awaitSpeakCompletion', true),
      ('setLanguage', 'en-US'),
      ('speak', 'Hello'),
      ('stop', null),
    ]);
    expect(DeviceSpeech(), isA<Speech>());
    expect(DeviceVoice(), isA<Voice>());
  });
}
