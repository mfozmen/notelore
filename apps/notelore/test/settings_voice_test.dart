import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  /// Settings, scrolled to the Whisper card.
  Future<void> openVoice(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Whisper speech recognition'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Lets the download's file work finish: real IO, outside the fake clock.
  Future<void> settle(WidgetTester tester, Session session) async {
    for (var i = 0; i < 100 && session.whisperProgress != null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('settings: download Whisper, then turn it off and on', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openVoice(tester);
    expect(find.textContaining('about 375 MB'), findsOneWidget);
    expect(find.text('Use Whisper in voice mode'), findsNothing); // not downloaded yet

    await tester.tap(find.text('Download Whisper'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Downloading…'), findsOneWidget);
    await settle(tester, session);
    expect(session.whisper.ready, isTrue);
    expect(find.text('Download Whisper'), findsNothing);

    await tester.tap(find.text('Use Whisper in voice mode'));
    await tester.pumpAndSettle();
    expect(session.useWhisper, isFalse);
    expect(session.speech, same(harness.speech));
  });

  testWidgets('settings: pick the microphone Whisper records from', (tester) async {
    phone(tester);
    final harness = Harness()..microphones = [(id: 'usb', label: 'USB mic')];
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openVoice(tester);
    expect(find.text('Microphone'), findsNothing); // only once Whisper is there
    await tester.tap(find.text('Download Whisper'));
    await settle(tester, session);
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB mic').last);
    await tester.pumpAndSettle();
    expect(session.microphone, 'usb');
    expect(find.text('USB mic'), findsOneWidget);
  });

  testWidgets('settings: a failed Whisper download says why', (tester) async {
    phone(tester);
    final harness = Harness()..modelPage = null;
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openVoice(tester);
    await tester.tap(find.text('Download Whisper'));
    await settle(tester, session);
    expect(find.textContaining('The download failed: w.onnx: HTTP 404'), findsOneWidget);
    expect(find.text('Download Whisper'), findsOneWidget); // try again
  });
}
