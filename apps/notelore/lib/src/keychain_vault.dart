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

  /// Writes run one after another, each saving the whole map.
  Future<void> _queue = Future.value();

  Future<Map<String, String>> _map() => _loaded ??= _load();

  Future<Map<String, String>> _load() async {
    final stored = await inner.read(key: _item);
    if (stored != null) return (jsonDecode(stored) as Map).cast<String, String>();
    // First run of this version: the per-secret items of older ones move in.
    final old = {
      for (final MapEntry(:key, :value) in (await inner.readAll()).entries)
        if (key.startsWith('$keySpace.')) key: value,
    };
    if (old.isNotEmpty) {
      await inner.write(key: _item, value: jsonEncode(old));
      for (final key in old.keys) {
        await inner.delete(key: key);
      }
    }
    return old;
  }

  Future<void> _change(void Function(Map<String, String> map) change) {
    final done = _queue.then((_) async {
      final map = await _map();
      change(map);
      await (map.isEmpty
          ? inner.delete(key: _item)
          : inner.write(key: _item, value: jsonEncode(map)));
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
  }) async => (await _map())[key];

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => (await _map()).containsKey(key);

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
  }) => _change((map) => value == null ? map.remove(key) : map[key] = value);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _change((map) => map.remove(key));

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _change((map) => map.clear());
}
