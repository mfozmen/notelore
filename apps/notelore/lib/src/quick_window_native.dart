/// The desktop's quick-add window (#800): the platform side of [QuickWindow],
/// a method channel to the Windows and macOS runners that `flutter test`
/// cannot reach.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'quick_window.dart';
import 'session.dart';

// coverage:ignore-start
const _channel = MethodChannel('io.github.mfozmen.notelore/quick');

class _ChannelHost implements QuickHost {
  @override
  String get keys => Platform.isMacOS ? '⌥⌘N' : 'Ctrl+Alt+N';

  @override
  Future<bool> listen({required bool on}) async =>
      await _channel.invokeMethod<bool>('listen', on) ?? false;

  @override
  Future<void> compact() => _channel.invokeMethod<void>('compact');

  @override
  Future<void> restore() => _channel.invokeMethod<void>('restore');

  @override
  Future<void> front() => _channel.invokeMethod<void>('front');
}

/// On Windows and macOS: the shortcut, as Settings says, opens the quick window.
void setUpQuickWindow(Session session) {
  if (!Platform.isWindows && !Platform.isMacOS) return;
  final quick = session.quickWindow = QuickWindow(session, _ChannelHost());
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'pressed') await quick.pressed();
  });
  // A runner without the channel (the tests' host) has no quick window.
  unawaited(
    quick.start().catchError((Object _) {
      quick.dispose();
      session.quickWindow = null;
    }, test: (error) => error is MissingPluginException),
  );
}
// coverage:ignore-end
