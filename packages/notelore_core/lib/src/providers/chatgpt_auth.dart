/// Signing in to use a ChatGPT Plus or Pro plan ("Sign in with ChatGPT", plan
/// usage for open-source and locally hosted apps):
/// https://developers.openai.com/siwc/token-sharing-open-source
///
/// The first sign-in registers Notelore with the user's account: the browser
/// comes back to a loopback callback with an issued client id, which is kept
/// with an opaque host id and reused from then on. Refresh tokens rotate, so
/// every refresh stores the new one.
library;

import 'dart:math';

import 'package:http/http.dart' as http;

import '../oauth.dart';
import 'http.dart';

const _authorize = 'https://auth.openai.com/api/accounts/authorize';
const _token = 'https://auth.openai.com/api/accounts/oauth/token';
const _resource = 'https://api.openai.com/v1';
const _planScope = 'chatgpt.tokens.use.direct';
const _scopes = 'openid profile email offline_access resource.invoke $_planScope';

/// Refresh errors after which only a new sign-in helps (OpenAI's list).
const _terminal = [
  'invalid_grant',
  'invalid_refresh_token',
  'token_expired',
  'refresh_token_expired',
  'refresh_token_invalidated',
  'refresh_token_reused',
];

class ChatGptAuth implements OAuthSignIn {
  ChatGptAuth({
    required this.openBrowser,
    required this.read,
    required this.write,
    http.Client? client,
    DateTime Function()? clock,
    this.wait = const Duration(minutes: 5),
    this.timeout = const Duration(seconds: 30),
    this.exchangeFor = const Duration(minutes: 2),
    this.retryEvery = const Duration(seconds: 2),
  }) : _client = client ?? http.Client(),
       clock = clock ?? DateTime.timestamp;

  final Future<void> Function(Uri url) openBrowser;

  /// The keystore: `client_id`, `host_id`, `refresh_token`, `id_token`.
  final Future<String?> Function(String name) read;

  /// Stores a value; null forgets it.
  final Future<void> Function(String name, String? value) write;
  final DateTime Function() clock;
  final Duration wait;
  final Duration timeout;

  /// How long the code exchange keeps trying while OpenAI cannot be reached,
  /// and how often: a phone holds back the network of an app behind the
  /// sign-in tab until the user is back in it.
  final Duration exchangeFor;
  final Duration retryEvery;
  final http.Client _client;

  String? _access;
  DateTime _expires = DateTime.utc(0);

  @override
  Future<bool> signedIn() async => await read('refresh_token') != null;

  @override
  Future<void> signIn() async {
    final saved = await read('client_id');
    final hostId = await read('host_id') ?? 'urn:uuid:${_uuid()}';
    await write('host_id', hostId);
    final idToken = await read('id_token');
    final verifier = randomSecret(48);
    final state = randomSecret(16);
    final (:query, :redirect) = await loopbackRedirect(
      path: '/auth/callback',
      service: 'ChatGPT',
      authorizeUrl: (redirect) => Uri.parse(_authorize).replace(
        queryParameters: {
          'client_id': saved ?? 'dynamic_agent_client',
          if (saved == null) 'agent_name_hint': 'Notelore',
          'ext_agent_host_id': hostId,
          'id_token_hint': ?idToken,
          'response_type': 'code',
          'redirect_uri': redirect,
          'scope': _scopes,
          'resource': _resource,
          'state': state,
          'nonce': randomSecret(16),
          'code_challenge': pkceChallenge(verifier),
          'code_challenge_method': 'S256',
        },
      ),
      state: state,
      openBrowser: openBrowser,
      wait: wait,
    );
    final clientId = saved ?? query['client_id'];
    if (clientId == null) {
      throw const SignInFailed('ChatGPT did not register Notelore', service: 'ChatGPT');
    }
    final tokens = await _exchange({
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': query['code']!,
      'code_verifier': verifier,
      'redirect_uri': redirect,
      'resource': _resource,
    });
    if (!'${tokens['scope']}'.split(' ').contains(_planScope)) {
      throw const SignInFailed('the ChatGPT plan was not shared with Notelore', service: 'ChatGPT');
    }
    await write('client_id', clientId);
    await _keep(tokens);
  }

  @override
  Future<String> token({bool refresh = false}) async {
    final valid =
        _access != null && clock().isBefore(_expires.subtract(const Duration(minutes: 1)));
    if (valid && !refresh) return _access!;
    // One refresh at a time: refresh tokens rotate, and reusing one is fatal.
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String>? _refreshing;

  Future<String> _refresh() async {
    final stored = await read('refresh_token');
    final clientId = await read('client_id');
    if (stored == null || clientId == null) {
      throw const NotSignedIn('not signed in with ChatGPT');
    }
    try {
      await _keep(
        await _post({
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'refresh_token': stored,
        }),
      );
    } on HttpError catch (error) {
      if (!_terminal.any(error.message.contains)) rethrow;
      await write('refresh_token', null); // the registration stays for the next sign-in
      throw const NotSignedIn('ChatGPT access was revoked or expired');
    }
    return _access!;
  }

  /// Keeps the access token in memory and the rotated refresh token stored.
  Future<void> _keep(Map<String, Object?> tokens) async {
    _access = tokens['access_token']! as String;
    _expires = clock().add(Duration(seconds: tokens['expires_in']! as int));
    await write('refresh_token', tokens['refresh_token']! as String);
    if (tokens['id_token'] case final String id) await write('id_token', id);
  }

  /// The code exchange, tried again while the network is held back.
  Future<Map<String, Object?>> _exchange(Map<String, String> form) async {
    final trying = Stopwatch()..start();
    while (true) {
      try {
        return await _post(form);
      } on NetworkError {
        if (trying.elapsed >= exchangeFor) rethrow;
        await Future<void>.delayed(retryEvery);
      }
    }
  }

  Future<Map<String, Object?>> _post(Map<String, String> form) =>
      postForm(_client, _token, form, timeout: timeout, service: 'ChatGPT');

  /// Forgets the tokens on this device. OpenAI has no revoke endpoint for this
  /// flow; the user disconnects Notelore in ChatGPT's settings.
  @override
  Future<void> signOut() async {
    _access = null;
    await write('refresh_token', null);
  }
}

/// A random (version 4) UUID.
String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
