import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:test/test.dart';

const timeout = Duration(seconds: 7);

void main() {
  test('POST sends JSON with headers and returns JSON', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response('{"ok": true}', 200);
    });
    final answer = await request(
      client,
      'POST',
      'https://api.x/v1',
      headers: {'x-api-key': 'k'},
      body: {'a': 'ş'},
      timeout: timeout,
    );
    expect(answer, {'ok': true});
    expect(sent.method, 'POST');
    expect(jsonDecode(utf8.decode(sent.bodyBytes)), {'a': 'ş'});
    expect(sent.headers['x-api-key'], 'k');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
  });

  test('GET without a body and an empty answer', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response('', 200);
    });
    expect(await request(client, 'GET', 'https://api.x/empty', timeout: timeout), isNull);
    expect(sent.method, 'GET');
    expect(sent.bodyBytes, isEmpty);
  });

  final errors = {
    'nested': ('{"error": {"message": "invalid x-api-key"}}', 'invalid x-api-key'),
    'flat': ('{"error": "model not found"}', 'model not found'), // Ollama
    'not-json': ('upstream timed out', 'upstream timed out'),
    'no-error-key': ('{"detail": "x"}', '{"detail": "x"}'),
  };
  for (final MapEntry(key: name, value: (body, message)) in errors.entries) {
    test('HTTP errors carry the status and the API message: $name', () async {
      final client = MockClient((_) async => http.Response(body, 401));
      await expectLater(
        request(client, 'GET', 'https://api.x', timeout: timeout),
        throwsA(
          isA<HttpError>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.message, 'message', message)
              .having((e) => '$e', 'string', 'HTTP 401: $message'),
        ),
      );
    });
  }

  test('a non-JSON success page is an HTTP error', () async {
    // A captive portal answers 200 with HTML; callers expect only HttpError or NetworkError.
    final client = MockClient(
      (_) async => http.Response('<html>Sign in to the hotel Wi-Fi</html>', 200),
    );
    await expectLater(
      request(client, 'GET', 'https://api.x/portal', timeout: timeout),
      throwsA(
        isA<HttpError>()
            .having((e) => e.status, 'status', 200)
            .having(
              (e) => e.message,
              'message',
              allOf(contains('not JSON'), contains('hotel Wi-Fi')),
            ),
      ),
    );
  });

  test('an unreachable server or a timeout is a network error', () async {
    final down = MockClient((_) async => throw http.ClientException('no route to host'));
    await expectLater(
      request(down, 'GET', 'https://api.x', timeout: timeout),
      throwsA(isA<NetworkError>().having((e) => '$e', 'string', contains('no route to host'))),
    );
    final slow = MockClient((_) => Completer<http.Response>().future);
    await expectLater(
      request(slow, 'GET', 'https://api.x', timeout: const Duration(milliseconds: 10)),
      throwsA(isA<NetworkError>()),
    );
  });

  test('the default transport talks real HTTP (to a loopback server)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'method': request.method, 'body': jsonDecode(body)}));
      await request.response.close();
    });
    final answer = await defaultTransport(
      'POST',
      'http://127.0.0.1:${server.port}/x',
      body: {'a': 1},
      timeout: timeout,
    );
    expect(answer, {
      'method': 'POST',
      'body': {'a': 1},
    });
  });
}
