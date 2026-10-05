/// JSON over HTTPS for the providers, on package:http.
///
/// No vendor SDKs: the same code runs on the desktop, Android and iOS. Every
/// failure is one of two exceptions, so callers can tell a rejected request
/// ([HttpError]) from an unreachable server ([NetworkError]).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The API answered with an error status (or with something that is not JSON);
/// [message] is the API's own text.
class HttpError implements Exception {
  const HttpError(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'HTTP $status: $message';
}

/// The server could not be reached, or did not answer in time.
class NetworkError implements Exception {
  const NetworkError(this.message);

  final String message;

  @override
  String toString() => 'NetworkError: $message';
}

/// Sends [body] as JSON and returns the decoded JSON answer (null for an empty one).
typedef Transport = Future<Object?> Function(
  String method,
  String url, {
  Map<String, String> headers,
  Object? body,
  required Duration timeout,
});

final _client = http.Client();

/// The transport the providers use unless a test hands them a fake.
Future<Object?> defaultTransport(
  String method,
  String url, {
  Map<String, String> headers = const {},
  Object? body,
  required Duration timeout,
}) => request(_client, method, url, headers: headers, body: body, timeout: timeout);

Future<Object?> request(
  http.Client client,
  String method,
  String url, {
  Map<String, String> headers = const {},
  Object? body,
  required Duration timeout,
}) async {
  final prepared = http.Request(method, Uri.parse(url))
    ..headers.addAll({'Content-Type': 'application/json', ...headers});
  if (body != null) prepared.bodyBytes = utf8.encode(jsonEncode(body));
  final http.Response answer;
  try {
    answer = await client.send(prepared).then(http.Response.fromStream).timeout(timeout);
  } on http.ClientException catch (error) {
    throw NetworkError(error.message);
  } on TimeoutException {
    throw NetworkError('no answer from $url within ${timeout.inSeconds} s');
  }
  final text = utf8.decode(answer.bodyBytes, allowMalformed: true);
  if (answer.statusCode >= 400) throw HttpError(answer.statusCode, _message(text));
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    // e.g. a captive portal's sign-in page answering 200
    final start = text.length > 200 ? text.substring(0, 200) : text;
    throw HttpError(answer.statusCode, 'the answer was not JSON: $start');
  }
}

/// The error text from {"error": {"message": ...}} or {"error": "..."}, else the raw body.
String _message(String text) {
  try {
    return switch (jsonDecode(text)) {
      {'error': {'message': final Object message}} => '$message',
      {'error': final Object error} => '$error',
      _ => text,
    };
  } on FormatException {
    return text;
  }
}
