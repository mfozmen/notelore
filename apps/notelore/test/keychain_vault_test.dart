import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/keychain_vault.dart';

/// The real plugin over its in-memory mock, counting what reaches the Keychain.
class _Counted extends FlutterSecureStorage {
  _Counted();

  var reads = 0;
  var writes = 0;

  /// The next Keychain read or write fails, as when the prompt is cancelled.
  var fail = false;

  void _maybeFail() {
    if (fail) {
      fail = false;
      throw Exception('cancelled');
    }
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
  }) {
    reads++;
    _maybeFail();
    return super.read(key: key);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    reads++;
    _maybeFail();
    return super.readAll();
  }

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
  }) {
    writes++;
    _maybeFail();
    return super.write(key: key, value: value);
  }
}

void main() {
  test('every secret lives in one Keychain item, read once a run (#648)', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final inner = _Counted();
    final vault = KeychainVault(inner, keySpace: 'notelore');
    await vault.write(key: 'notelore.openai.api_key', value: 'sk-1');
    await vault.write(key: 'notelore.lock', value: 'hash');
    expect(await const FlutterSecureStorage().readAll(), {
      'notelore.vault': jsonEncode({'notelore.openai.api_key': 'sk-1', 'notelore.lock': 'hash'}),
    });

    final again = _Counted();
    final next = KeychainVault(again, keySpace: 'notelore');
    expect(await next.read(key: 'notelore.openai.api_key'), 'sk-1');
    expect(await next.read(key: 'notelore.lock'), 'hash');
    expect(await next.read(key: 'notelore.gone'), isNull);
    expect(await next.containsKey(key: 'notelore.lock'), isTrue);
    expect(await next.readAll(), {'notelore.openai.api_key': 'sk-1', 'notelore.lock': 'hash'});
    expect(again.reads, 1, reason: 'one item, one password prompt');
  });

  test('a value written as null, or deleted, leaves the item', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final vault = KeychainVault(_Counted(), keySpace: 'notelore');
    await vault.write(key: 'notelore.a', value: '1');
    await vault.write(key: 'notelore.b', value: '2');
    await vault.write(key: 'notelore.a', value: null);
    await vault.delete(key: 'notelore.b');
    expect(await vault.readAll(), isEmpty);
    await vault.write(key: 'notelore.c', value: '3');
    await vault.deleteAll();
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('the items of an older version move into the one item, once', () async {
    FlutterSecureStorage.setMockInitialValues({
      'notelore.openai.api_key': 'sk-old',
      'notelore.lock': 'hash',
      'notelore-dev.openai.api_key': 'sk-dev',
    });
    final inner = _Counted();
    final vault = KeychainVault(inner, keySpace: 'notelore');
    expect(await vault.read(key: 'notelore.openai.api_key'), 'sk-old');
    expect(await const FlutterSecureStorage().readAll(), {
      'notelore.vault': jsonEncode({'notelore.openai.api_key': 'sk-old', 'notelore.lock': 'hash'}),
      'notelore-dev.openai.api_key': 'sk-dev', // another key space is not ours to move
    });

    final later = _Counted();
    expect(await KeychainVault(later, keySpace: 'notelore').read(key: 'notelore.lock'), 'hash');
    expect(later.reads, 1);
  });

  test('writes in a row each keep the others', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final vault = KeychainVault(_Counted(), keySpace: 'notelore');
    await Future.wait([for (var i = 0; i < 5; i++) vault.write(key: 'notelore.k$i', value: '$i')]);
    final fresh = KeychainVault(_Counted(), keySpace: 'notelore');
    expect((await fresh.readAll()).length, 5);
  });

  test('macOS gets the vault; the other systems keep one item a secret', () {
    const plain = FlutterSecureStorage();
    expect(keysFor(plain, os: 'macos', keySpace: 'notelore'), isA<KeychainVault>());
    expect(keysFor(plain, os: 'windows', keySpace: 'notelore'), same(plain));
  });

  test('a write the Keychain refused is not reported as saved', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final inner = _Counted();
    final vault = KeychainVault(inner, keySpace: 'notelore');
    await vault.write(key: 'notelore.a', value: '1');
    inner.fail = true;
    await expectLater(vault.write(key: 'notelore.a', value: '2'), throwsException);
    expect(await vault.read(key: 'notelore.a'), '1');
    await vault.write(key: 'notelore.b', value: '3');
    expect(await vault.readAll(), {'notelore.a': '1', 'notelore.b': '3'});
  });

  test('a first read that failed is tried again, not kept failing', () async {
    FlutterSecureStorage.setMockInitialValues({
      'notelore.vault': jsonEncode({'notelore.a': '1'}),
    });
    final inner = _Counted()..fail = true;
    final vault = KeychainVault(inner, keySpace: 'notelore');
    await expectLater(vault.read(key: 'notelore.a'), throwsException);
    expect(await vault.read(key: 'notelore.a'), '1');
  });
}
