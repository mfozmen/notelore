import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/oauth.dart';
import 'package:notelore_core/src/providers/chatgpt_auth.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:test/test.dart';

/// OpenAI's token endpoint, in memory: it registers the app on the first sign-in
/// and rotates the refresh token on every refresh.
class FakeOpenAI {
  final forms = <Map<String, String>>[];
  var issued = 0;
  var refresh = 'refresh-1';
  String? errorCode; // a terminal refresh error to answer with
  var scope = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';

  late final client = MockClient((request) async {
    final form = Uri.splitQueryString(request.body);
    forms.add(form);
    if (form['grant_type'] == 'refresh_token') {
      if (errorCode != null) return http.Response('{"error": "$errorCode"}', 400);
      if (form['refresh_token'] != refresh) return http.Response('{"error": "invalid_grant"}', 400);
    }
    refresh = 'refresh-${++issued + 1}';
    return http.Response(
      jsonEncode({
        'access_token': 'access-$issued',
        'refresh_token': refresh,
        'id_token': 'id-$issued',
        'expires_in': 3600,
        'scope': scope,
      }),
      200,
    );
  });
}

void main() {
  late FakeOpenAI openai;
  late Map<String, String> store;
  late DateTime now;
  setUp(() {
    openai = FakeOpenAI();
    store = {};
    now = DateTime.utc(2026, 10, 11, 12);
  });

  /// A browser that signs in and comes back with [query] (or a code, and the
  /// issued client id on a first registration).
  Future<void> Function(Uri) browser({List<Uri>? opened, Map<String, String>? query}) =>
      (url) async {
        opened?.add(url);
        final params = url.queryParameters;
        final answer =
            query ??
            {
              'code': 'the-code',
              'state': params['state']!,
              if (params['client_id'] == 'dynamic_agent_client') 'client_id': 'oaiapp_123',
            };
        unawaited(() async {
          final client = HttpClient();
          final redirect = Uri.parse(params['redirect_uri']!).replace(queryParameters: answer);
          final response = await (await client.getUrl(redirect)).close();
          await response.drain<void>();
          client.close();
        }());
      };

  ChatGptAuth auth({Future<void> Function(Uri)? openBrowser, http.Client? client}) => ChatGptAuth(
    openBrowser: openBrowser ?? browser(),
    read: (name) async => store[name],
    write: (name, value) async => value == null ? store.remove(name) : store[name] = value,
    client: client ?? openai.client,
    clock: () => now,
    wait: const Duration(seconds: 5),
  );

  test('first sign-in registers Notelore and keeps the issued client id', () async {
    final opened = <Uri>[];
    final a = auth(openBrowser: browser(opened: opened));
    expect(await a.signedIn(), isFalse);
    await a.signIn();
    final params = opened.single.queryParameters;
    expect(opened.single.host, 'auth.openai.com');
    expect(opened.single.path, '/api/accounts/authorize');
    expect(params['client_id'], 'dynamic_agent_client');
    expect(params['agent_name_hint'], 'Notelore');
    expect(params['ext_agent_host_id'], startsWith('urn:uuid:'));
    expect(params['scope'], contains('chatgpt.tokens.use.direct'));
    expect(params['resource'], 'https://api.openai.com/v1');
    expect(params['code_challenge_method'], 'S256');
    expect(params['redirect_uri'], matches(RegExp(r'^http://127\.0\.0\.1:\d+/auth/callback$')));
    expect(params['nonce'], isNotEmpty);
    final exchange = openai.forms.single;
    expect(exchange['client_id'], 'oaiapp_123'); // the issued one, not the placeholder
    expect(exchange['redirect_uri'], params['redirect_uri']);
    expect(exchange['resource'], 'https://api.openai.com/v1');
    expect(store['client_id'], 'oaiapp_123');
    expect(store['host_id'], params['ext_agent_host_id']);
    expect(store['refresh_token'], 'refresh-2');
    expect(await a.signedIn(), isTrue);
    expect(await a.token(), 'access-1');
  });

  test('a later sign-in reuses the client id, host id and id token', () async {
    store.addAll({'client_id': 'oaiapp_123', 'host_id': 'urn:uuid:h', 'id_token': 'id-0'});
    final opened = <Uri>[];
    await auth(openBrowser: browser(opened: opened)).signIn();
    final params = opened.single.queryParameters;
    expect(params['client_id'], 'oaiapp_123');
    expect(params['ext_agent_host_id'], 'urn:uuid:h');
    expect(params['id_token_hint'], 'id-0');
    expect(params.containsKey('agent_name_hint'), isFalse);
  });

  test('a sign-in that did not share the plan is refused', () async {
    openai.scope = 'openid profile email';
    await expectLater(
      auth().signIn(),
      throwsA(isA<SignInFailed>().having((e) => '$e', 'message', contains('ChatGPT plan'))),
    );
    expect(store.containsKey('refresh_token'), isFalse);
  });

  test('a first registration without an issued client id is refused', () async {
    await expectLater(
      auth(
        openBrowser: (url) =>
            browser(query: {'code': 'the-code', 'state': url.queryParameters['state']!})(url),
      ).signIn(),
      throwsA(isA<SignInFailed>()),
    );
  });

  test('tokens are reused until near expiry, then refreshed with rotation', () async {
    store.addAll({'client_id': 'oaiapp_123', 'refresh_token': 'refresh-1'});
    final a = auth();
    expect(await a.token(), 'access-1');
    expect(store['refresh_token'], 'refresh-2'); // rotated and kept
    expect(await a.token(), 'access-1');
    now = now.add(const Duration(minutes: 59, seconds: 30));
    expect(await a.token(), 'access-2');
    expect(await a.token(refresh: true), 'access-3');
    expect(openai.forms.last, containsPair('client_id', 'oaiapp_123'));
    expect(openai.forms.last, containsPair('grant_type', 'refresh_token'));
  });

  test('a terminal refresh error asks to sign in again; offline does not', () async {
    await expectLater(auth().token(), throwsA(isA<NotSignedIn>()));
    store.addAll({'client_id': 'oaiapp_123', 'refresh_token': 'refresh-1'});
    openai.errorCode = 'refresh_token_reused';
    await expectLater(
      auth().token(),
      throwsA(isA<NotSignedIn>().having((e) => e.message, 'message', contains('ChatGPT'))),
    );
    expect(store.containsKey('refresh_token'), isFalse);
    expect(store['client_id'], 'oaiapp_123'); // the registration stays
    store['refresh_token'] = 'refresh-1';
    final offline = MockClient((_) async => throw http.ClientException('no route'));
    await expectLater(auth(client: offline).token(), throwsA(isA<NetworkError>()));
    expect(store['refresh_token'], 'refresh-1');
    openai.errorCode = null;
    final broken = MockClient((_) async => http.Response('{"error": "server_error"}', 500));
    await expectLater(auth(client: broken).token(), throwsA(isA<HttpError>()));
    expect(store['refresh_token'], 'refresh-1');
  });

  test('sign out forgets the tokens and keeps the registration', () async {
    store.addAll({
      'client_id': 'oaiapp_123',
      'host_id': 'urn:uuid:h',
      'refresh_token': 'r',
      'id_token': 'i',
    });
    await auth().signOut();
    expect(store, {'client_id': 'oaiapp_123', 'host_id': 'urn:uuid:h', 'id_token': 'i'});
  });

  test('the default clock, wait and client', () {
    final a = ChatGptAuth(
      openBrowser: (_) async {},
      read: (_) async => null,
      write: (_, _) async {},
    );
    expect(a.wait, const Duration(minutes: 5));
    expect(a.clock().isUtc, isTrue);
  });
}
