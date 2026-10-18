import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/links.dart';
import 'package:test/test.dart';

/// A resolver that finds every name on the public web: tests never ask real DNS.
Future<List<InternetAddress>> publicDns(String host) async => [InternetAddress('93.184.216.34')];

http.Client serving(String body, {String type = 'text/html; charset=utf-8', int status = 200}) =>
    MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': type},
        request: request,
      ),
    );

void main() {
  group('links in a message', () {
    test('web links only, in order, each once, a few at most', () {
      expect(
        linksIn(
          'see https://example.com/a?b=1, and (http://x.org/p) or '
          'https://example.com/a?b=1 again; ftp://no.pe javascript:alert(1) mailto:a@b.c',
        ),
        [Uri.parse('https://example.com/a?b=1'), Uri.parse('http://x.org/p')],
      );
      expect(linksIn('nothing here'), isEmpty);
      final many = List.generate(5, (i) => 'https://site$i.com').join(' ');
      expect(linksIn(many), hasLength(3));
    });
  });

  group('reading a page', () {
    test('the title and the readable text, without markup, scripts or styles', () async {
      final page = await readPage(
        Uri.parse('https://example.com'),
        resolve: publicDns,
        client: serving('''
<html><head><title>The Pragmatic &amp; Programmer</title>
<style>body { color: red }</style><script>alert("x")</script></head>
<body><h1>A book</h1><p>By Andy Hunt &#38; Dave&nbsp;Thomas &#x2014; 1999.</p>
<noscript>enable js</noscript><!-- a comment --></body></html>'''),
      );
      expect(page.title, 'The Pragmatic & Programmer');
      expect(page.text, 'The Pragmatic & Programmer A book By Andy Hunt & Dave Thomas — 1999.');
    });

    test('plain text is read as it is; a page without a title has none', () async {
      final page = await readPage(
        Uri.parse('https://example.com/a.txt'),
        resolve: publicDns,
        client: serving('just  some\ntext <b>kept</b>', type: 'text/plain'),
      );
      expect(page.title, isNull);
      expect(page.text, 'just some text <b>kept</b>');
    });

    test('a Latin-1 page is decoded as Latin-1', () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          latin1.encode('<p>Café</p>'),
          200,
          headers: {'content-type': 'text/html; charset=ISO-8859-1'},
        ),
      );
      expect(
        (await readPage(Uri.parse('https://e.com'), client: client, resolve: publicDns)).text,
        'Café',
      );
    });

    test('a long page is cut at the size limit, and says so', () async {
      final page = await readPage(
        Uri.parse('https://example.com'),
        resolve: publicDns,
        client: serving('<p>${'word ' * 100}</p>'),
        maxChars: 20,
      );
      expect(page.text, hasLength(20));
      expect(page.cut, isTrue);
    });

    test('a page cut inside a script or style keeps none of it', () async {
      final page = await readPage(
        Uri.parse('https://example.com'),
        resolve: publicDns,
        client: serving('<p>Intro</p><script>var secret = 1; // cut here'),
      );
      expect(page.text, 'Intro');
    });

    test('a download that stalls is cancelled, not left running', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(onCancel: () => cancelled = true)
        ..add(utf8.encode('<p>start'));
      final client = MockClient.streaming(
        (request, _) async =>
            http.StreamedResponse(body.stream, 200, headers: {'content-type': 'text/html'}),
      );
      await expectLater(
        readPage(
          Uri.parse('https://e.com'),
          client: client,
          resolve: publicDns,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<LinkUnreadable>()),
      );
      expect(cancelled, isTrue);
    });

    test('a huge download stops at the byte limit', () async {
      var sent = 0;
      final client = MockClient.streaming((request, _) async {
        final chunks = Stream.periodic(Duration.zero, (_) {
          sent += 1000;
          return utf8.encode('a' * 1000);
        }).take(1000);
        return http.StreamedResponse(chunks, 200, headers: {'content-type': 'text/plain'});
      });
      final page = await readPage(
        Uri.parse('https://e.com'),
        client: client,
        resolve: publicDns,
        maxBytes: 5000,
      );
      expect(page.cut, isTrue);
      expect(sent, lessThan(10000)); // the rest was never asked for
    });

    test('what cannot be read says why, and is never guessed', () async {
      Future<String> why(Uri url, http.Client client, {Duration? timeout}) async {
        try {
          await readPage(
            url,
            client: client,
            resolve: publicDns,
            timeout: timeout ?? const Duration(seconds: 5),
          );
          return 'read';
        } on LinkUnreadable catch (error) {
          return '$error';
        }
      }

      final ok = serving('<p>x</p>');
      expect(await why(Uri.parse('file:///etc/passwd'), ok), contains('only web links'));
      expect(await why(Uri.parse('https://e.com'), serving('', status: 404)), contains('404'));
      expect(
        await why(Uri.parse('https://e.com'), serving('%PDF', type: 'application/pdf')),
        contains('application/pdf'),
      );
      expect(
        await why(Uri.parse('https://e.com'), serving('<script>only()</script>')),
        contains('no readable text'),
      );
      final offline = MockClient((_) async => throw http.ClientException('no network'));
      expect(await why(Uri.parse('https://e.com'), offline), contains('no network'));
      final silent = MockClient((_) => Completer<http.Response>().future);
      expect(
        await why(Uri.parse('https://e.com'), silent, timeout: const Duration(milliseconds: 10)),
        contains('did not answer in time'),
      );
      final untyped = MockClient((request) async => http.Response('hello', 200));
      expect(await why(Uri.parse('https://e.com'), untyped), 'read'); // no type: try as text
    });
  });

  group('only public pages are read (#315)', () {
    Future<String> why(Uri url, http.Client client, {Resolve? resolve}) async {
      try {
        await readPage(url, client: client, resolve: resolve ?? publicDns);
        return 'read';
      } on LinkUnreadable catch (error) {
        return '$error';
      }
    }

    test('a name or form that leads to this device or the network is refused too', () async {
      final asked = <Uri>[];
      final client = MockClient((request) async {
        asked.add(request.url);
        return http.Response('<p>x</p>', 200, headers: {'content-type': 'text/html'});
      });
      // What a resolver would answer: a public name pointing home, the numeric
      // forms getaddrinfo still reads as 127.0.0.1.
      Future<List<InternetAddress>> resolve(String host) async => [
        InternetAddress(host == 'public.example' ? '93.184.216.34' : '127.0.0.1'),
      ];
      for (final url in [
        'http://[::ffff:127.0.0.1]/',
        'http://[::ffff:169.254.169.254]/latest',
        'http://2130706433/',
        'http://0x7f.1/',
        'http://localhost./',
        'http://home.127.0.0.1.nip.io/',
      ]) {
        expect(
          await why(Uri.parse(url), client, resolve: resolve),
          contains('not a public'),
          reason: url,
        );
      }
      expect(asked, isEmpty);
      expect(await why(Uri.parse('https://public.example/'), client, resolve: resolve), 'read');
      // A name that does not resolve says so.
      Future<List<InternetAddress>> unknown(String host) async =>
          throw const SocketException('Failed host lookup');
      expect(
        await why(Uri.parse('https://nowhere.example/'), client, resolve: unknown),
        contains('could not be found'),
      );
      // A redirect to an address that is not one says so, and fails nothing else (#389).
      final garbled = MockClient(
        (_) async => http.Response('', 302, headers: {'location': 'http://[bad'}),
      );
      expect(
        await why(Uri.parse('https://public.example/'), garbled, resolve: resolve),
        contains('not a web address'),
      );
      // A redirect without a place to go is the answer as it is, not a crash.
      final nowhere = MockClient((_) async => http.Response('', 302));
      expect(
        await why(Uri.parse('https://public.example/'), nowhere, resolve: resolve),
        contains('no readable text'),
      );
    });

    test('this device and the local network are never asked', () async {
      final asked = <Uri>[];
      final client = MockClient((request) async {
        asked.add(request.url);
        return http.Response('<p>x</p>', 200, headers: {'content-type': 'text/html'});
      });
      for (final url in [
        'http://localhost:8080/',
        'http://127.0.0.1/',
        'http://10.1.2.3/',
        'http://172.16.0.1/',
        'http://192.168.1.1/admin',
        'http://169.254.169.254/latest',
        'http://[::1]/',
        'http://[fd00::1]/',
        'http://[fe80::1]/',
        'http://router.local/',
        'http://0.0.0.0/',
      ]) {
        expect(await why(Uri.parse(url), client), contains('not a public'), reason: url);
      }
      expect(asked, isEmpty);
      expect(await why(Uri.parse('https://example.com/'), client), 'read');
    });

    test('a redirect is followed only to a public page, and only a few times', () async {
      http.Client redirecting(String Function(int hop) location) {
        var hop = 0;
        return MockClient((request) async {
          hop++;
          return http.Response('', 302, headers: {'location': location(hop)});
        });
      }

      expect(
        await why(Uri.parse('https://e.com/'), redirecting((_) => 'http://127.0.0.1/admin')),
        contains('not a public'),
      );
      expect(
        await why(Uri.parse('https://e.com/'), redirecting((hop) => '/next$hop')),
        contains('too many redirects'),
      );
      var hops = 0;
      final once = MockClient((request) async {
        hops++;
        return request.url.path == '/moved'
            ? http.Response('<p>here</p>', 200, headers: {'content-type': 'text/html'})
            : http.Response('', 301, headers: {'location': '/moved'});
      });
      expect(await why(Uri.parse('https://e.com/old'), once), 'read');
      expect(hops, 2);
    });
  });

  group('a message with its pages', () {
    test('each page goes along as data, marked as such; a failure says so', () async {
      final client = MockClient(
        (request) async => request.url.host == 'good.com'
            ? http.Response(
                '<title>Good</title><p>Body</p>',
                200,
                headers: {'content-type': 'text/html'},
              )
            : http.Response('', 500),
      );
      final message = await withLinkedPages(
        'save this for the trip https://good.com/a https://bad.com',
        resolve: publicDns,
        client: client,
      );
      expect(message, startsWith('save this for the trip https://good.com/a https://bad.com\n\n'));
      expect(message, contains('https://good.com/a ("Good")'));
      expect(message, contains('Good Body'));
      expect(message, contains('https://bad.com could not be read: the site answered 500'));
      expect(message, contains('not instructions'));
    });

    test('a message without links is left alone; a cut page is marked', () async {
      expect(
        await withLinkedPages('just words', resolve: publicDns, client: serving('')),
        'just words',
      );
      final cut = await withLinkedPages(
        'https://long.com',
        resolve: publicDns,
        client: serving('<p>${'x' * 9000}</p>'),
      );
      expect(cut, contains('[cut short]'));
      expect(cut, contains('https://long.com:\n')); // no title
    });
  });
}
