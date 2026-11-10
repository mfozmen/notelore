import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/watch_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('io.github.mfozmen.notelore/watch');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a message goes to the watch through the channel', () async {
    final calls = <MethodCall>[];
    var connected = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return connected;
    });
    final link = WatchLink();
    expect(await link.send('/notelore/answer', 'Postgres'), isTrue);
    connected = false;
    expect(await link.send('/notelore/answer', 'lost'), isFalse);
    expect(calls.first.method, 'send');
    expect(calls.first.arguments, {'path': '/notelore/answer', 'text': 'Postgres'});
  });

  test('no answer from the platform counts as not sent', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await WatchLink().send('/notelore/answer', 'x'), isFalse);
  });

  test('on a platform without the watch glue nothing is sent', () async {
    expect(await WatchLink().send('/notelore/answer', 'x'), isFalse);
  });

  test('messages from the watch reach the listener', () async {
    final heard = <(String, String)>[];
    WatchLink().listen((path, text) => heard.add((path, text)));
    Future<void> deliver(String method, Object? arguments) => messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
    await deliver('message', {'path': '/notelore/say', 'text': 'buy milk'});
    await deliver('unknown', null);
    expect(heard, [('/notelore/say', 'buy milk')]);
  });
}
