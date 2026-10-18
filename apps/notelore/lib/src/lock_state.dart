/// The app lock (#224): whether opening Notelore asks for a PIN or password,
/// the wait after wrong tries, and locking again after a while away. Only the
/// secret's salted hash is kept, in the keystore: never in the notes or on Drive.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:notelore_core/notelore_core.dart';

class AppLock {
  AppLock({
    required this.keys,
    required this.keySpace,
    required this.clock,
    required this.uptime,
    required this.iterations,
    required this.offThread,
    required this.changed,
  });

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
    enabled = locked = await keys.read(key: _lockKey) != null;
    await _loadFailures();
  }

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
    if (wait > Duration.zero) return false;
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

  /// Turns the lock on (or changes it) with [secret]; only its hash is kept.
  Future<void> set(String secret) async {
    final iterations = this.iterations;
    final hash = await offThread(() => hashSecret(secret, iterations: iterations));
    await keys.write(key: _lockKey, value: hash);
    await _clearFailures();
    enabled = true;
    changed();
  }

  /// Turns the lock off when [current] is its PIN or password. Nothing else
  /// goes: notes, keys and settings stay.
  Future<bool> remove(String current) async {
    if (!await _tryOpen(current)) return false;
    await keys.delete(key: _lockKey);
    enabled = locked = false;
    changed();
    return true;
  }

  /// Whether [secret] opens the lock; with no lock set, anything does.
  Future<bool> _matches(String secret) async {
    final stored = await keys.read(key: _lockKey);
    return stored == null || await offThread(() => verifySecret(secret, stored));
  }
}
