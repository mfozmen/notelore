import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:notelore_core/src/sync/google_auth.dart';
import 'package:test/test.dart';

/// Google's token endpoint, in memory.
class FakeGoogle {
  final calls = <Map<String, String>>[];
  var refreshToken = 'refresh-1';
  var revoked = false;
  var issued = 0;
  var failRevoke = false;
  String? verifier;

  late final client = MockClient((request) async {
    if (request.url.path == '/revoke') {
      if (failRevoke) throw http.ClientException('offline');
      revoked = true;
      return http.Response('', 200);
    }
    final form = Uri.splitQueryString(request.body);
    calls.add(form);
    if (form['grant_type'] == 'authorization_code') {
      verifier = form['code_verifier'];
      if (form['code'] != 'the-code') return http.Response('{"error": "invalid_grant"}', 400);
      return _tokens(withRefresh: true);
    }
    if (form['refresh_token'] != refreshToken || revoked) {
      return http.Response(
        '{"error": "invalid_grant", "error_description": "Token has been expired or revoked."}',
        400,
      );
    }
    return _tokens(withRefresh: false);
  });

  http.Response _tokens({required bool withRefresh}) => http.Response(
    jsonEncode({
      'access_token': 'access-${++issued}',
      'expires_in': 3600,
      if (withRefresh) 'refresh_token': refreshToken,
    }),
    200,
  );
}

void main() {
  late FakeGoogle google;
  late String? stored;
  late DateTime now;
  setUp(() {
    google = FakeGoogle();
    stored = null;
    now = DateTime.utc(2026, 10, 5, 12);
  });

  /// A browser that signs in (or answers with [query]) on the redirect it was sent to.
  /// Like a real one, opening it returns at once; the redirect arrives later.
  Future<void> Function(Uri) browser({Map<String, String>? query, List<Uri>? opened}) =>
      (url) async {
        opened?.add(url);
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        final answer = query ?? {'code': 'the-code', 'state': url.queryParameters['state']!};
        unawaited(() async {
          final client = HttpClient();
          final response = await (await client.getUrl(redirect.replace(queryParameters: answer)))
              .close();
          await response.drain<void>();
          client.close();
        }());
      };

  LoopbackAuth auth({Future<void> Function(Uri)? openBrowser, Duration? wait}) => LoopbackAuth(
    clientId: 'client-id',
    clientSecret: 'client-secret',
    openBrowser: openBrowser ?? browser(),
    readRefreshToken: () async => stored,
    saveRefreshToken: (token) async => stored = token,
    client: google.client,
    clock: () => now,
    wait: wait ?? const Duration(seconds: 5),
  );

  test('sign in: browser, loopback redirect, PKCE code exchange, token kept', () async {
    final opened = <Uri>[];
    final a = auth(openBrowser: browser(opened: opened));
    expect(await a.signedIn(), isFalse);
    await a.signIn();
    final url = opened.single;
    expect(url.host, 'accounts.google.com');
    expect(url.queryParameters['scope'], 'https://www.googleapis.com/auth/drive.file');
    expect(url.queryParameters['access_type'], 'offline');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['redirect_uri'], startsWith('http://127.0.0.1:'));
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(google.verifier!)).bytes)
        .replaceAll('=', '');
    expect(url.queryParameters['code_challenge'], challenge);
    expect(google.calls.single['client_secret'], 'client-secret');
    expect(google.calls.single['redirect_uri'], url.queryParameters['redirect_uri']);
    expect(stored, 'refresh-1');
    expect(await a.signedIn(), isTrue);
    expect(await a.token(), 'access-1'); // from the sign-in itself
  });

  test('the access token is reused until it expires, then refreshed', () async {
    stored = 'refresh-1';
    final a = auth();
    expect(await a.token(), 'access-1');
    expect(await a.token(), 'access-1');
    now = now.add(const Duration(minutes: 59, seconds: 30)); // within a minute of expiry
    expect(await a.token(), 'access-2');
    expect(await a.token(refresh: true), 'access-3');
    expect(google.calls.last['grant_type'], 'refresh_token');
  });

  test('without a stored token, or after it was revoked, it is not signed in', () async {
    final a = auth();
    await expectLater(
      a.token(),
      throwsA(isA<NotSignedIn>().having((e) => '$e', 'message', 'not signed in to Google Drive')),
    );
    stored = 'refresh-1';
    google.revoked = true;
    await expectLater(a.token(), throwsA(isA<NotSignedIn>()));
    expect(stored, isNull); // a dead token is forgotten
  });

  test('a token endpoint failure that is not a revocation is reported as it is', () async {
    stored = 'refresh-1';
    final a = LoopbackAuth(
      clientId: 'c',
      clientSecret: 's',
      openBrowser: (_) async {},
      readRefreshToken: () async => stored,
      saveRefreshToken: (token) async => stored = token,
      client: MockClient((_) async => http.Response('{"error": "server_error"}', 500)),
    );
    await expectLater(a.token(), throwsA(isA<HttpError>()));
    expect(stored, 'refresh-1');
  });

  test('the user saying no, a forged redirect or a bad code all fail the sign-in', () async {
    await expectLater(
      auth(openBrowser: browser(query: {'error': 'access_denied'})).signIn(),
      throwsA(isA<SignInFailed>().having((e) => '$e', 'message', contains('access_denied'))),
    );
    await expectLater(
      auth(openBrowser: browser(query: {'code': 'the-code', 'state': 'forged'})).signIn(),
      throwsA(isA<SignInFailed>()),
    );
    await expectLater(
      auth(
        openBrowser: (url) =>
            browser(query: {'code': 'wrong', 'state': url.queryParameters['state']!})(url),
      ).signIn(),
      throwsA(isA<HttpError>()),
    );
    expect(stored, isNull);
  });

  test('offline while refreshing is a NetworkError, so the sync says offline', () async {
    stored = 'refresh-1';
    final down = LoopbackAuth(
      clientId: 'c',
      clientSecret: 's',
      openBrowser: (_) async {},
      readRefreshToken: () async => stored,
      saveRefreshToken: (token) async => stored = token,
      client: MockClient((_) async => throw http.ClientException('no route to host')),
    );
    await expectLater(down.token(), throwsA(isA<NetworkError>()));
    final slow = LoopbackAuth(
      clientId: 'c',
      clientSecret: 's',
      openBrowser: (_) async {},
      readRefreshToken: () async => stored,
      saveRefreshToken: (token) async => stored = token,
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(slow.token(), throwsA(isA<NetworkError>()));
    expect(stored, 'refresh-1'); // offline is not a revocation
  });

  test('stray requests to the loopback port do not end the sign-in', () async {
    Future<void> strayThenSignIn(Uri url) async {
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      final client = HttpClient();
      final favicon = await (await client.getUrl(redirect.replace(path: '/favicon.ico'))).close();
      expect(favicon.statusCode, 404);
      await favicon.drain<void>();
      client.close();
      await browser()(url);
    }

    await auth(openBrowser: strayThenSignIn).signIn();
    expect(stored, 'refresh-1');
  });

  test('a browser that never comes back times out', () async {
    await expectLater(
      auth(openBrowser: (_) async {}, wait: const Duration(milliseconds: 50)).signIn(),
      throwsA(isA<SignInFailed>().having((e) => '$e', 'message', contains('timed out'))),
    );
  });

  test('sign out revokes the token and forgets it, even offline', () async {
    stored = 'refresh-1';
    await auth().signOut();
    expect(google.revoked, isTrue);
    expect(stored, isNull);
    stored = 'refresh-1';
    google.failRevoke = true;
    await auth().signOut();
    expect(stored, isNull);
    await auth().signOut(); // nothing stored: nothing to do
  });

  test('the default clock and wait', () {
    final a = LoopbackAuth(
      clientId: 'c',
      clientSecret: 's',
      openBrowser: (_) async {},
      readRefreshToken: () async => null,
      saveRefreshToken: (_) async {},
    );
    expect(a.wait, const Duration(minutes: 5));
    expect(a.clock().isUtc, isTrue);
  });
}
