/// Every secret of a key space in one Keychain item (#648). An ad-hoc signed Mac
/// app is not on any item's access list after an update, so macOS asks for the
/// login password once per item it reads; one item means one prompt.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [keys] as this system should use them: the vault on macOS only. Windows'
/// Credential Manager caps an item at about 2.5 KB, and nothing else prompts.
FlutterSecureStorage keysFor(
  FlutterSecureStorage keys, {
  required String os,
  required String keySpace,
}) => os == 'macos' ? KeychainVault(keys, keySpace: keySpace) : keys;

class KeychainVault extends FlutterSecureStorage {
  KeychainVault(this.inner, {required this.keySpace});

  final FlutterSecureStorage inner;
  final String keySpace;

  String get _item => '$keySpace.vault';

  Future<Map<String, String>>? _loaded;

  Future<void> _queue = Future.value();

  // A cancelled prompt must not fail every later read of the run.
  Future<Map<String, String>> _map() => _loaded ??= _load().catchError((Object e, StackTrace s) {
    _loaded = null;
    Error.throwWithStackTrace(e, s);
  });

  Future<Map<String, String>> _load() async {
    final stored = await inner.read(key: _item);
    return stored == null ? {} : (jsonDecode(stored) as Map).cast<String, String>();
  }

  /// Each key's look for its item of its own from before the vault, this run,
  /// shared by reads at the same time. A look that failed is forgotten, so the
  /// next read tries again.
  final _looks = <String, Future<void>>{};

  /// After [deleteAll] no older item is moved in this run. Items never asked for
  /// stay in the Keychain and move in on a later run.
  var _cleared = false;

  /// [key]'s value. An older version's item of its own moves into the vault the
  /// first time it is asked for, never by listing: macOS's file-based keychain
  /// refuses to list items with their data (errSecParam, #666).
  Future<String?> _value(String key) async {
    if (!(await _map()).containsKey(key) && !_cleared) {
      await (_looks[key] ??= _moveOld(key).catchError((Object e, StackTrace s) {
        _looks.remove(key);
        Error.throwWithStackTrace(e, s);
      }));
    }
    return (await _map())[key];
  }

  Future<void> _moveOld(String key) async {
    final old = await inner.read(key: key);
    if (old == null) return;
    // A write made while this read waited is newer: it stays.
    await _change((map) => map.putIfAbsent(key, () => old));
    await _dropOld(key);
  }

  /// Sets or removes [key]; its older item goes too, so it cannot come back.
  Future<void> _set(String key, String? value) async {
    final fresh = !_cleared && !_looks.containsKey(key);
    if (fresh) _looks[key] = Future.value();
    await _change((map) => value == null ? map.remove(key) : map[key] = value);
    if (fresh) await _dropOld(key);
  }

  Future<void> _dropOld(String key) async {
    try {
      await inner.delete(key: key);
    } on Object {
      // Left behind unused: the vault answers first.
    }
  }

  Future<void> _change(void Function(Map<String, String> map) change) {
    final done = _queue.then((_) async {
      final map = await _map();
      final next = {...map};
      change(next);
      await (next.isEmpty
          ? inner.delete(key: _item)
          : inner.write(key: _item, value: jsonEncode(next)));
      map
        ..clear()
        ..addAll(next);
    });
    _queue = done.catchError((Object _) {});
    return done;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _value(key);

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => await _value(key) != null;

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => {...await _map()};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _set(key, value);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _set(key, null);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    _cleared = true;
    return _change((map) => map.clear());
  }
}
