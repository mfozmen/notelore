/// Signing in to Google Drive.
///
/// [DriveAuth] is what the sync needs: a sign-in step and fresh access tokens.
/// [LoopbackAuth] implements it on the desktop with Google's loopback flow for
/// installed apps: the system browser signs in and redirects to a one-shot
/// server on 127.0.0.1, the code is exchanged with PKCE, and only the refresh
/// token is kept (in the platform keystore, through the callbacks). The client
/// secret of a desktop client is not confidential, by Google's own design;
/// it is injected at build time all the same and never committed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../providers/http.dart';
import 'drive.dart';

abstract interface class DriveAuth {
  Future<bool> signedIn();

  /// Interactive: may open a browser or a system sheet.
  Future<void> signIn();

  /// A valid access token for [driveScope]; [refresh] after one was refused.
  /// Throws [NotSignedIn] when the user has to sign in (again).
  Future<String> token({bool refresh = false});

  Future<void> signOut();
}

/// There is no usable Google sign-in: never signed in, or access was revoked.
class NotSignedIn implements Exception {
  const NotSignedIn([this.message = 'not signed in to Google Drive']);

  final String message;

  @override
  String toString() => message;
}

/// The interactive sign-in did not complete.
class SignInFailed implements Exception {
  const SignInFailed(this.message);

  final String message;

  @override
  String toString() => 'Google sign-in failed: $message';
}

const _authorize = 'https://accounts.google.com/o/oauth2/v2/auth';
const _token = 'https://oauth2.googleapis.com/token';
const _revoke = 'https://oauth2.googleapis.com/revoke';
const _page =
    '<!doctype html><meta charset="utf-8"><title>Notelore</title>'
    '<p style="font-family:sans-serif">You can close this tab and go back to Notelore.</p>';

class LoopbackAuth implements DriveAuth {
  LoopbackAuth({
    required this.clientId,
    required this.clientSecret,
    required this.openBrowser,
    required this.readRefreshToken,
    required this.saveRefreshToken,
    http.Client? client,
    DateTime Function()? clock,
    this.wait = const Duration(minutes: 5),
  }) : _client = client ?? http.Client(),
       clock = clock ?? DateTime.timestamp;

  final String clientId;
  final String clientSecret;
  final Future<void> Function(Uri url) openBrowser;
  final Future<String?> Function() readRefreshToken;

  /// Stores the refresh token; null forgets it.
  final Future<void> Function(String? token) saveRefreshToken;
  final DateTime Function() clock;

  /// How long the sign-in waits for the browser to come back.
  final Duration wait;
  final http.Client _client;

  String? _access;
  DateTime _expires = DateTime.utc(0);

  @override
  Future<bool> signedIn() async => await readRefreshToken() != null;

  @override
  Future<void> signIn() async {
    final random = Random.secure();
    String secret(int bytes) =>
        base64Url.encode(List.generate(bytes, (_) => random.nextInt(256))).replaceAll('=', '');
    final verifier = secret(48);
    final state = secret(16);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      // Listening before the browser opens: its redirect can come back at once.
      final arrival = server.first.timeout(wait);
      await openBrowser(
        Uri.parse(_authorize).replace(
          queryParameters: {
            'client_id': clientId,
            'redirect_uri': redirect,
            'response_type': 'code',
            'scope': driveScope,
            'access_type': 'offline',
            'prompt': 'consent', // always hand out a refresh token
            'state': state,
            'code_challenge': base64Url
                .encode(sha256.convert(ascii.encode(verifier)).bytes)
                .replaceAll('=', ''),
            'code_challenge_method': 'S256',
          },
        ),
      );
      final HttpRequest request;
      try {
        request = await arrival;
      } on TimeoutException {
        throw const SignInFailed('timed out waiting for the browser');
      }
      final answer = request.uri.queryParameters;
      request.response
        ..headers.contentType = ContentType.html
        ..write(_page);
      await request.response.close();
      if (answer['error'] case final error?) throw SignInFailed(error);
      if (answer['state'] != state || answer['code'] == null) {
        throw const SignInFailed('the answer did not come from this sign-in');
      }
      final tokens = await _post({
        'grant_type': 'authorization_code',
        'code': answer['code']!,
        'redirect_uri': redirect,
        'code_verifier': verifier,
      });
      await saveRefreshToken(tokens['refresh_token']! as String);
      _keep(tokens);
    } finally {
      await server.close(force: true);
    }
  }

  @override
  Future<String> token({bool refresh = false}) async {
    final valid =
        _access != null && clock().isBefore(_expires.subtract(const Duration(minutes: 1)));
    if (valid && !refresh) return _access!;
    final stored = await readRefreshToken();
    if (stored == null) throw const NotSignedIn();
    try {
      _keep(await _post({'grant_type': 'refresh_token', 'refresh_token': stored}));
    } on HttpError catch (error) {
      if (error.status != 400 || !error.message.contains('invalid_grant')) rethrow;
      await saveRefreshToken(null); // revoked or expired for good: sign in again
      throw const NotSignedIn('Google Drive access was revoked or expired; connect again');
    }
    return _access!;
  }

  void _keep(Map<String, Object?> tokens) {
    _access = tokens['access_token']! as String;
    _expires = clock().add(Duration(seconds: tokens['expires_in']! as int));
  }

  Future<Map<String, Object?>> _post(Map<String, String> form) async {
    final response = await _client.post(
      Uri.parse(_token),
      body: {...form, 'client_id': clientId, 'client_secret': clientSecret},
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 400) throw HttpError(response.statusCode, text);
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  /// Forgets the token here and, best effort, revokes it at Google.
  @override
  Future<void> signOut() async {
    final stored = await readRefreshToken();
    _access = null;
    if (stored == null) return;
    await saveRefreshToken(null);
    try {
      await _client.post(Uri.parse(_revoke), body: {'token': stored});
    } on http.ClientException {
      // offline: the token is gone from this device, which is what matters
    }
  }
}
