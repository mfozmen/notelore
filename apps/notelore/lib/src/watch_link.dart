/// Messages to and from the Wear OS watch app over the Wearable Data Layer
/// (docs/wear-os.md). MainActivity.kt holds the MessageClient glue; tests fake
/// the channel.
library;

import 'package:flutter/services.dart';

class WatchLink {
  WatchLink([this._channel = const MethodChannel('io.github.mfozmen.notelore/watch')]);

  final MethodChannel _channel;

  /// Sends [text] on [path] to every connected watch; false when none is.
  Future<bool> send(String path, String text) async =>
      await _channel.invokeMethod<bool>('send', {'path': path, 'text': text}) ?? false;

  /// Calls [onMessage] for each message the watch sends.
  void listen(void Function(String path, String text) onMessage) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'message') return;
      final message = call.arguments as Map<Object?, Object?>;
      onMessage(message['path']! as String, message['text']! as String);
    });
  }
}
