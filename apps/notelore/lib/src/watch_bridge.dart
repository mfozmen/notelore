import 'dart:io';

import 'package:flutter/services.dart';

import 'session.dart';

const watchChannel = 'io.github.mfozmen.notelore/watch';

/// An answer for a message the watch sent (#823); the Kotlin side passes it
/// back over the Wearable Data Layer.
void listenForWatch(Session session) {
  if (Platform.isAndroid) listenForWatchOn(session, const MethodChannel(watchChannel));
}

/// The same, on a given channel (tests use their own).
void listenForWatchOn(Session session, MethodChannel channel) {
  channel.setMethodCallHandler((call) async {
    if (call.method != 'ask') return null;
    return session.askFromWatch('${call.arguments ?? ''}');
  });
}
