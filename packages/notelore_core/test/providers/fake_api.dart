import 'package:notelore_core/src/providers/http.dart';

/// A fake transport: every provider test runs against it, never the network.
/// Answers come from a queue (an Exception is thrown) and every call is recorded.
class Api {
  final answers = <Object?>[];
  final calls = <Map<String, Object?>>[];

  Map<String, Object?> get last => calls.last;

  Future<Object?> call(
    String method,
    String url, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
  }) async {
    calls.add({'method': method, 'url': url, 'headers': headers, 'body': body, 'timeout': timeout});
    final answer = answers.removeAt(0);
    if (answer is Exception) throw answer;
    return answer;
  }

  Transport get transport => call;
}
