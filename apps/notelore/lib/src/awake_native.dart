/// Android glue for [Awake] (#409): a short foreground service while a sign-in
/// waits in the browser, so the system does not freeze the app and its
/// loopback server still hears the answer. Native code `flutter test` cannot
/// run; [AwakeSignIn] around it is tested with a fake.
library;

import 'package:flutter/services.dart';

import 'drive_auth.dart' show Awake;

// coverage:ignore-start
class NativeAwake implements Awake {
  const NativeAwake();

  static const _channel = MethodChannel('io.github.mfozmen.notelore/awake');

  @override
  Future<void> hold() => _call('hold');

  @override
  Future<void> release() => _call('release');

  /// Best effort: a device that cannot hold (an old build, no service) still
  /// signs in, as before.
  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // not held: the sign-in goes on regardless
    } on MissingPluginException {
      // not held: the sign-in goes on regardless
    }
  }
}
// coverage:ignore-end
