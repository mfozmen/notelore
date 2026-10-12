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

  testWidgets('settings: Whisper arrives by itself; then pick its microphone', (tester) async {
    phone(tester);
    final harness = Harness()
      ..modelPage = 'whisper bytes'
      ..microphones = [];
    final session = await pumpApp(tester, harness); // opening the app starts the download
    await connect(tester, key: 'k');
    await openVoice(tester);
    expect(find.textContaining('about 375 MB'), findsOneWidget);
    await settle(tester, session);
    expect(session.whisper.ready, isTrue);
    expect(find.text('Download Whisper'), findsNothing);
    // A headset plugged in while Settings is open: listed again on request.
    harness.microphones = [(id: 'usb', label: 'USB mic')];
    await tester.tap(find.byTooltip('List the microphones again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB mic').last);
    await tester.pumpAndSettle();
    expect(session.microphone, 'usb');
    expect(find.text('USB mic'), findsOneWidget);
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
