/// What the OAuth sign-ins share (Google Drive on the desktop, the ChatGPT
/// plan): the sign-in interface, PKCE, the one-shot loopback redirect server
/// and token-endpoint form posts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'providers/http.dart';

/// A sign-in that hands out access tokens.
abstract interface class OAuthSignIn {
  Future<bool> signedIn();

  /// Interactive: may open a browser or a system sheet.
  Future<void> signIn();

  /// A valid access token; [refresh] after one was refused. Throws
  /// [NotSignedIn] when the user has to sign in (again).
  Future<String> token({bool refresh = false});

  Future<void> signOut();
}

/// There is no usable sign-in: never signed in, or access was revoked.
class NotSignedIn implements Exception {
  const NotSignedIn([this.message = 'not signed in to Google Drive']);

  final String message;

  @override
  String toString() => message;
}

/// The interactive sign-in did not complete.
class SignInFailed implements Exception {
  const SignInFailed(this.message, {this.service = 'Google'});

  final String message;
  final String service;

  @override
  String toString() => '$service sign-in failed: $message';
}

final _random = Random.secure();

/// [bytes] random bytes, base64url without padding: PKCE verifiers, state, nonce.
String randomSecret(int bytes) =>
    base64Url.encode(List.generate(bytes, (_) => _random.nextInt(256))).replaceAll('=', '');

/// The S256 PKCE challenge of [verifier].
String pkceChallenge(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

const _page =
    '<!doctype html><meta charset="utf-8"><title>Notelore</title>'
    '<p style="font-family:sans-serif">You can close this tab and go back to Notelore.</p>';

/// Opens the authorization page built by [authorizeUrl] for a loopback
/// redirect on 127.0.0.1 ([path] on a free port) and waits up to [wait] for the
/// browser to come back. Returns the callback's query and the redirect URI used.
/// Throws [SignInFailed] for a refusal, a timeout or a callback whose `state`
/// is not [state].
Future<({Map<String, String> query, String redirect})> loopbackRedirect({
  required Uri Function(String redirect) authorizeUrl,
  required String state,
  required Future<void> Function(Uri url) openBrowser,
  required Duration wait,
  String path = '',
  String service = 'Google',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final redirect = 'http://127.0.0.1:${server.port}$path';
    // Listening before the browser opens: its redirect can come back at once.
    // Anything else on the port (a favicon fetch, a prefetch) gets a 404.
    final arrival = server.firstWhere(_isRedirect).timeout(wait);
    await openBrowser(authorizeUrl(redirect));
    final HttpRequest request;
    try {
      request = await arrival;
    } on TimeoutException {
      throw SignInFailed('timed out waiting for the browser', service: service);
    }
    final query = request.uri.queryParameters;
    request.response
      ..headers.contentType = ContentType.html
      ..write(_page);
    await request.response.close();
    if (query['error'] case final error?) throw SignInFailed(error, service: service);
    if (query['state'] != state || query['code'] == null) {
      throw SignInFailed('the answer did not come from this sign-in', service: service);
    }
    return (query: query, redirect: redirect);
  } finally {
    await server.close(force: true);
  }
}

bool _isRedirect(HttpRequest request) {
  final query = request.uri.queryParameters;
  if (query.containsKey('code') || query.containsKey('error')) return true;
  request.response.statusCode = HttpStatus.notFound;
  unawaited(request.response.close());
  return false;
}

/// POSTs [form] to a token endpoint and returns the JSON answer. An error
/// status is an [HttpError] with the raw body; no answer is a [NetworkError].
Future<Map<String, Object?>> postForm(
  http.Client client,
  String url,
  Map<String, String> form, {
  required Duration timeout,
  required String service,
}) async {
  final http.Response response;
  try {
    response = await client.post(Uri.parse(url), body: form).timeout(timeout);
  } on http.ClientException catch (error) {
    throw NetworkError(error.message);
  } on TimeoutException {
    throw NetworkError('$service sign-in did not answer in time');
  }
  final text = utf8.decode(response.bodyBytes);
  if (response.statusCode >= 400) throw HttpError(response.statusCode, text);
  return (jsonDecode(text) as Map).cast<String, Object?>();
}
