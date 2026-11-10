import 'package:flutter/services.dart';

import 'session.dart';

const watchChannel = 'io.github.mfozmen.notelore/watch';

/// An answer for a message the watch sent (#823); the Kotlin side passes it
/// back over the Wearable Data Layer. Tests give their own channel.
void listenForWatch(Session session, {MethodChannel channel = const MethodChannel(watchChannel)}) {
  channel.setMethodCallHandler((call) async {
    if (call.method != 'ask') return null;
    return session.askFromWatch('${call.arguments ?? ''}');
  });
}
