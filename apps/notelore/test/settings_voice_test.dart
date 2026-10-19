import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  /// Settings, scrolled to the Whisper card.
  Future<void> openVoice(WidgetTester tester) async {
    await openSettings(tester, 'Voice');
    await tester.scrollUntilVisible(
      find.text('Whisper speech recognition'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Until the download is over: its file work is real IO, outside the fake clock.
  Future<void> settle(WidgetTester tester, Session session) =>
      settleUntil(tester, () => session.whisperProgress == null);

  testWidgets('settings: a download slower than a second still arrives (#365)', (tester) async {
    phone(tester);
    final served = Completer<void>();
    // A real timer, outside the fake clock: the download takes 4 s of real
    // time, as one can when the whole suite runs at once.
    Zone.root.run(() => Timer(const Duration(seconds: 4), served.complete));
    final harness = Harness()
      ..modelPage = 'whisper bytes'
      ..modelGate = served.future;
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await settle(tester, session);
    expect(session.whisper.ready, isTrue);
  });

  testWidgets('settings: Whisper arrives by itself; then pick its microphone', (tester) async {
    phone(tester);
    final harness = Harness()
      ..modelPage = 'whisper bytes'
      ..microphones = [];
    final session = await pumpApp(tester, harness); // opening the app starts the download
    await connect(tester, key: 'k');
    await openVoice(tester);
    expect(find.text('Whisper speech recognition'), findsOneWidget);
    expect(find.textContaining('375 MB'), findsNothing); // no explanation, just the setting
    await settle(tester, session);
    expect(session.whisper.ready, isTrue);
    expect(find.text('Download Whisper'), findsNothing);
    // A headset plugged in while Settings is open: listed again on request.
    harness.microphones = [(id: 'usb', label: 'USB mic')];
    await tester.tap(find.byTooltip('List the microphones again'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('microphone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB mic').last);
    await tester.pumpAndSettle();
    expect(session.microphone, 'usb');
    expect(find.text('USB mic'), findsOneWidget); // shown as the choice
  });

  testWidgets('settings: a failed Whisper download says why, and tries again', (tester) async {
    phone(tester);
    final harness = Harness(); // the model is not served: the download fails
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openVoice(tester);
    await settle(tester, session);
    expect(find.textContaining('The download failed: w.onnx: HTTP 404'), findsOneWidget);

    harness.modelPage = 'whisper bytes';
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Downloading…'), findsOneWidget);
    await settle(tester, session);
    expect(session.whisper.ready, isTrue);
    expect(find.text('Microphone'), findsOneWidget);
  });
}
