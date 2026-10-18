/// The app lock (#224, #295): whether opening Notelore asks for the device's
/// own lock or a Notelore pattern or PIN, the wait after wrong tries, and
/// locking again after a while away. Only a pattern's or PIN's salted hash is
/// kept, in the keystore: never in the notes or on Drive; the device lock keeps
/// no secret at all.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:notelore_core/notelore_core.dart';

import 'device_auth.dart';

/// What opens the app: nothing, the device's own lock, or a Notelore pattern
/// or PIN. A password is a lock set before #295: it keeps working until changed.
enum LockKind { none, device, pattern, pin, password }

/// A PIN anyone tries first: one digit repeated, or a run up or down such as
/// 1234 or 9876 (#412).
bool weakPin(String pin) {
  final digits = [for (final unit in pin.codeUnits) unit - 0x30];
  final steps = {for (var i = 1; i < digits.length; i++) digits[i] - digits[i - 1]};
  return steps.length == 1 && steps.single.abs() <= 1;
}

/// The shapes people draw most, as dots 0 to 8: an L, a Z, a U, a C, a 7 and
/// the ring round the edge; drawn either way round (#412).
const _commonShapes = {
  '0-3-6-7-8',
  '0-1-2-4-6-7-8',
  '0-3-6-7-8-5-2',
  '2-1-0-3-6-7-8',
  '0-1-2-5-8',
  '0-1-2-5-8-7-6-3',
};

/// Whether [pattern] is one of the shapes people draw most.
bool weakPattern(String pattern) =>
    _commonShapes.contains(pattern) ||
    _commonShapes.contains(pattern.split('-').reversed.join('-'));

class AppLock {
  AppLock({
    required this.keys,
    required this.keySpace,
    required this.clock,
    required this.uptime,
    required this.iterations,
    required this.offThread,
    required this.changed,
    required this.device,
  });

  /// The device's own lock, asked for [LockKind.device].
  final DeviceAuth device;

  /// What the keystore holds instead of a hash for the device lock.
  static const _deviceMarker = 'device';

  final FlutterSecureStorage keys;
  final String keySpace;
  final DateTime Function() clock;

  /// Time that only moves forward: setting the clock ahead does not end a wait (#315).
  final Duration Function() uptime;

  /// The hash's strength, and where its slow hashing runs (off the UI thread,
  /// so a phone does not stutter while it checks a PIN).
  final int iterations;
  final Future<R> Function<R>(FutureOr<R> Function() work) offThread;

  /// Tells the screens something changed.
  final void Function() changed;

  /// Reads whether a lock is set (then the app starts locked) and the wrong tries so far.
  Future<void> load() async {
    final stored = await keys.read(key: _lockKey);
    kind = switch (stored) {
      null => LockKind.none,
      _deviceMarker => LockKind.device,
      _ => switch (await keys.read(key: _kindKey)) {
        'pattern' => LockKind.pattern,
        'pin' => LockKind.pin,
        _ => LockKind.password,
      },
    };
    enabled = locked = stored != null;
    await _loadFailures();
  }

  /// Which kind a pattern or PIN is, beside its hash.
  String get _kindKey => '$_lockKey.kind';

  /// What opens the app now.
  var kind = LockKind.none;

  /// Where the app lock's hash lives: the keystore, never the notes or Drive.
  String get _lockKey => '$keySpace.lock';

  /// Whether opening the app asks for a PIN or password.
  var enabled = false;

  /// Closed until [unlock] gets the right PIN or password; only when [enabled].
  var locked = false;

  /// How long the app may be in the background before it locks again: a
  /// phone keeps it in memory for hours, but a quick look elsewhere (the
  /// ChatGPT sign-in tab, a share sheet, a file picker) must not lock.
  static const relockAfter = Duration(minutes: 1);

  /// When the app went to the background; null while it is in front.
  DateTime? _awaySince;

  /// The app went to the background (hidden or paused); the first one counts.
  void backgrounded() => _awaySince ??= clock();

  /// The app is in front again: locked when it was away [relockAfter] or longer.
  void foregrounded() {
    final since = _awaySince;
    _awaySince = null;
    if (!enabled || locked || since == null) return;
    if (clock().difference(since) < relockAfter) return;
    locked = true;
    changed();
  }

  /// Wrong tries in a row and when the last one was, kept in the keystore
  /// beside the hash so a restart does not wipe them.
  String get _failuresKey => '$_lockKey.failures';
  var _failures = 0;
  DateTime? _lastFailure;

  /// [uptime] at the last wrong try in this run; a restart has only the clock.
  Duration? _failedAt;

  /// How long a run of [failures] wrong tries makes the next one wait: nothing
  /// for the first four, then 30 seconds, a minute, and five minutes from the
  /// seventh on (a 4-digit PIN has only 10,000 values).
  static Duration delay(int failures) => switch (failures) {
    < 5 => Duration.zero,
    5 => const Duration(seconds: 30),
    6 => const Duration(minutes: 1),
    _ => const Duration(minutes: 5),
  };

  /// What is left of the wait before the next try; zero when one may try now.
  Duration get wait {
    final last = _lastFailure;
    if (last == null) return Duration.zero;
    final byClock = last.add(delay(_failures)).difference(clock());
    final failedAt = _failedAt;
    final byUptime = failedAt == null ? Duration.zero : delay(_failures) - (uptime() - failedAt);
    final left = byClock > byUptime ? byClock : byUptime;
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _loadFailures() async {
    final saved = await keys.read(key: _failuresKey);
    final decoded = saved == null ? null : _decodeFailures(saved);
    _failures = decoded?.$1 ?? 0;
    _lastFailure = decoded?.$2;
    // A run of wrong tries that earned a wait starts it again in full: after a
    // restart only the clock knows how long it ran, and the clock can be set
    // ahead (#412). The right PIN or pattern, after the wait, clears it all.
    if (delay(_failures) > Duration.zero) _failedAt = uptime();
  }

  static (int, DateTime)? _decodeFailures(String saved) {
    try {
      if (jsonDecode(saved) case {'count': final int count, 'last': final String last}) {
        return (count, DateTime.parse(last));
      }
    } on FormatException {
      // damaged: start over
    }
    return null;
  }

  Future<void> _clearFailures() async {
    _failures = 0;
    _lastFailure = null;
    _failedAt = null;
    await keys.delete(key: _failuresKey);
  }

  /// Opens the app when [secret] is the lock's PIN or password; not while a
  /// wait after wrong tries runs ([wait]).
  Future<bool> unlock(String secret) async {
    if (!await _tryOpen(secret)) return false;
    locked = false;
    changed();
    return true;
  }

  /// Whether [secret] is the lock's, counting a wrong one and refusing any while
  /// a wait runs: opening and turning the lock off both go through here (#315).
  Future<bool> _tryOpen(String secret) async {
    if (wait > Duration.zero || kind == LockKind.device) return false;
    if (await _matches(secret)) {
      await _clearFailures();
      return true;
    }
    _failures++;
    _lastFailure = clock();
    _failedAt = uptime();
    await keys.write(
      key: _failuresKey,
      value: jsonEncode({'count': _failures, 'last': _lastFailure!.toIso8601String()}),
    );
    changed();
    return false;
  }

  /// Turns the lock on (or changes it) with a Notelore [secret] of [kind]
  /// (a pattern or a PIN); only its hash is kept.
  Future<void> set(String secret, {LockKind kind = LockKind.pin}) async {
    final iterations = this.iterations;
    final hash = await offThread(() => hashSecret(secret, iterations: iterations));
    await keys.write(key: _lockKey, value: hash);
    await keys.write(key: _kindKey, value: kind.name);
    await _clearFailures();
    enabled = true;
    this.kind = kind;
    changed();
  }

  /// Whether this device has a lock of its own to ask.
  Future<bool> deviceAvailable() => device.available();

  /// Turns on the device's own lock, once the device says the person may: the
  /// one who turns it on must be able to open it.
  Future<bool> useDevice(String reason) async {
    if (!await device.available() || !await _askDevice(reason)) return false;
    await keys.write(key: _lockKey, value: _deviceMarker);
    await keys.delete(key: _kindKey);
    await _clearFailures();
    enabled = true;
    kind = LockKind.device;
    changed();
    return true;
  }

  /// Opens the app when the device's lock says yes. The device counts its own
  /// wrong tries, so a cancel here starts no wait.
  Future<bool> unlockWithDevice(String reason) async {
    if (kind != LockKind.device || !await _askDevice(reason)) return false;
    locked = false;
    changed();
    return true;
  }

  /// Turns the device lock off when the device says yes.
  Future<bool> removeWithDevice(String reason) async {
    if (kind != LockKind.device || !await _askDevice(reason)) return false;
    await _off();
    return true;
  }

  /// The device's prompt. On Android its PIN or pattern screen is an activity
  /// of its own, so the time spent there is not time away: whatever it says,
  /// coming back does not lock again.
  Future<bool> _askDevice(String reason) async {
    final passed = await device.authenticate(reason);
    _awaySince = null;
    return passed;
  }

  Future<void> _off() async {
    await keys.delete(key: _lockKey);
    await keys.delete(key: _kindKey);
    enabled = locked = false;
    kind = LockKind.none;
    changed();
  }

  /// Turns the lock off when [current] is its pattern, PIN or password (the
  /// device lock goes with [removeWithDevice]). Nothing else goes: notes, keys
  /// and settings stay.
  Future<bool> remove(String current) async {
    if (!await _tryOpen(current)) return false;
    await _off();
    return true;
  }

  /// Whether [secret] opens the lock; with no lock set, anything does, and no
  /// text opens the device lock.
  Future<bool> _matches(String secret) async {
    final stored = await keys.read(key: _lockKey);
    if (stored == _deviceMarker) return false;
    return stored == null || await offThread(() => verifySecret(secret, stored));
  }
}
