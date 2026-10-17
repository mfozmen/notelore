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

/// The ChatGPT account signed in, but has no plan it may share with other
/// apps (only Plus and Pro can, #321): no retry helps, another way in does.
class NoChatGptPlan extends SignInFailed {
  const NoChatGptPlan()
    : super('the ChatGPT plan was not shared with Notelore', service: 'ChatGPT');
}

final _random = Random.secure();

/// [bytes] random bytes, base64url without padding: PKCE verifiers, state, nonce.
String randomSecret(int bytes) =>
    base64Url.encode(List.generate(bytes, (_) => _random.nextInt(256))).replaceAll('=', '');

/// The S256 PKCE challenge of [verifier].
String pkceChallenge(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

/// What the browser shows once the sign-in is back: on a phone it sends the
/// browser on to [returnTo], the app (#301); a link stays for browsers that
/// hold the redirect back.
String _page(Uri? returnTo) {
  final back = returnTo == null
      ? null
      : const HtmlEscape(HtmlEscapeMode.attribute).convert('$returnTo');
  return '<!doctype html><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '${back == null ? '' : '<meta http-equiv="refresh" content="0;url=$back">'}'
      '<title>Notelore</title>'
      '<body style="font-family:system-ui,sans-serif;display:flex;flex-direction:column;'
      'align-items:center;justify-content:center;min-height:90vh;margin:0 24px;'
      'text-align:center;color:#1b1c1c">'
      '<h1 style="font-size:24px;font-weight:600;margin:0 0 8px">Signed in</h1>'
      '${back == null ? '<p style="margin:0;color:#5c5f5f">You can close this tab and go back to Notelore.</p>' : '<a href="$back" style="margin-top:16px;padding:14px 28px;border-radius:24px;'
                'background:#00695c;color:#fff;text-decoration:none;font-weight:600">Back to Notelore</a>'}';
}

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
  Uri? returnTo,
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
      ..write(_page(returnTo));
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
