/// The device's own lock (#295): pattern, PIN, password, fingerprint or face on
/// Android; Windows Hello; Touch ID or the account password on macOS. Notelore
/// stores no secret for it: the system asks, and says only whether it passed.
library;

import 'package:local_auth/local_auth.dart';

/// Asks the device's own lock.
abstract interface class DeviceAuth {
  /// Whether this device has a lock the app can ask: false without one set
  /// up, or on a platform without one.
  Future<bool> available();

  /// Whether the person passed the device's lock now; [reason] is shown in its
  /// prompt. A cancel or a failed try is false.
  Future<bool> authenticate(String reason);
}

// coverage:ignore-start
/// [DeviceAuth] through local_auth, device credentials allowed: a pattern or
/// PIN works where there is no fingerprint.
class LocalDeviceAuth implements DeviceAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false; // no plugin on this platform, or no lock to ask
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on Object {
      return false; // locked out, not set up, or the prompt could not show: closed
    }
  }
}

// coverage:ignore-end
