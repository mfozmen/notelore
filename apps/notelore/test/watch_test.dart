import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/watch_bridge.dart';

import 'app_test.dart' show connect, pumpApp;
import 'support.dart';

void main() {
  testWidgets('the watch asks over the channel and gets the answer (#823)', (tester) async {
    final session = await pumpApp(tester, Harness(answers: ['Tamam.']));
    await connect(tester, key: 'k');
    final channel = const MethodChannel('notelore.watch.test');
    listenForWatch(session, channel: channel);
    const codec = StandardMethodCodec();

    Future<Object?> ask(Object? text) {
      final reply = Completer<ByteData?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('ask', text)),
        reply.complete,
      );
      return reply.future.then((data) => data == null ? null : codec.decodeEnvelope(data));
    }

    expect(await ask('selam'), 'Tamam.');
    expect(await ask(''), 'empty');
  });
}
