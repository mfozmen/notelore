/// GPT on the user's ChatGPT Plus or Pro plan, over the Responses API with a
/// "Sign in with ChatGPT" token ([ChatGptAuth]):
/// https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
///
/// The plan route has rules: every request streams (`stream: true`) and stores
/// nothing (`store: false`), so the whole history goes in `input`; the system
/// prompt is `instructions`, never a system message; function tools come in a
/// namespace. The answer is read from the stream's final `response` object.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../oauth.dart';
import 'base.dart';
import 'http.dart';

const _api = 'https://api.openai.com/v1';
const _namespace = 'notelore';

/// Where a user sees and manages what their plan has left.
const chatGptUsageUrl = 'https://chatgpt.com/settings/usage';

/// A valid access token; [refresh] after one was refused.
typedef BearerToken = Future<String> Function({bool refresh});

/// The ChatGPT plan has no allowance left for Notelore right now.
class PlanLimitReached implements Exception {
  const PlanLimitReached();

  @override
  String toString() =>
      "Your ChatGPT plan's usage limit for Notelore is reached. Manage usage: $chatGptUsageUrl";
}

class ChatGptProvider implements LlmProvider {
  ChatGptProvider(
    this.model,
    this.token, {
    http.Client? client,
    this.timeout = const Duration(seconds: 120),
  }) : _client = client ?? http.Client();

  @override
  final String model;
  final BearerToken token;

  /// How long one answer may take, streaming included.
  final Duration timeout;
  final http.Client _client;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final body = {
      'model': model,
      if (system.isNotEmpty) 'instructions': system,
      'input': toResponsesInput(messages),
      if (tools.isNotEmpty)
        'tools': [
          {
            'type': 'namespace',
            'name': _namespace,
            'description': "Notelore's note tools.",
            'tools': [
              for (final t in tools)
                {
                  'type': 'function',
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.inputSchema,
                },
            ],
          },
        ],
      'store': false,
      'stream': true,
    };
    final response = await _send(
      _client,
      token,
      'POST',
      '$_api/responses',
      body: body,
    ).then(_finalResponse).timeout(timeout, onTimeout: () => throw _slow());
    return fromResponse(response);
  }
}

NetworkError _slow() => const NetworkError('ChatGPT did not answer in time');

/// The stream's final `response`: from `response.completed`, or
/// `response.incomplete` (an answer cut short). `response.failed` throws.
Future<Map<String, Object?>> _finalResponse(http.StreamedResponse answer) async {
  final lines = answer.stream.transform(utf8.decoder).transform(const LineSplitter());
  try {
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final event = jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
      switch (event['type']) {
        case 'response.completed' || 'response.incomplete':
          return (event['response']! as Map).cast<String, Object?>();
        case 'response.failed':
          final error = ((event['response']! as Map)['error'] as Map?) ?? const {};
          throw _apiError(200, error);
      }
    }
  } on http.ClientException catch (error) {
    throw NetworkError(error.message);
  }
  throw const NetworkError('the ChatGPT answer stopped before it was complete');
}

/// Sends a request with the plan's bearer token, refreshing it once on a 401.
/// Error statuses become [PlanLimitReached], [NotSignedIn] or [HttpError].
Future<http.StreamedResponse> _send(
  http.Client client,
  BearerToken token,
  String method,
  String url, {
  Object? body,
}) async {
  for (var refresh = false; ; refresh = true) {
    final request = http.Request(method, Uri.parse(url))
      ..headers['Authorization'] = 'Bearer ${await token(refresh: refresh)}';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final http.StreamedResponse answer;
    try {
      answer = await client.send(request);
    } on http.ClientException catch (error) {
      throw NetworkError(error.message);
    }
    if (answer.statusCode == 401 && !refresh) continue; // expired: refresh once
    if (answer.statusCode < 400) return answer;
    final text = await answer.stream.bytesToString();
    final error = switch (_json(text)) {
      {'error': final Map<String, Object?> error} => error,
      _ => <String, Object?>{'message': text},
    };
    throw _apiError(answer.statusCode, error);
  }
}

Object? _json(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

Exception _apiError(int status, Map<Object?, Object?> error) => switch (error['code']) {
  'subscription_sharing_usage_limit_exceeded' ||
  'subscription_sharing_usage_unavailable' => const PlanLimitReached(),
  'subscription_sharing_invalid_user' => const NotSignedIn(
    'ChatGPT no longer lets Notelore use the plan; sign in again',
  ),
  _ => HttpError(status, '${error['message'] ?? error['code']}'),
};

/// The Anthropic-shaped history as Responses `input` items.
List<Map<String, Object?>> toResponsesInput(List<Message> messages) => [
  for (final message in messages)
    if (splitBlocks(message['content']) case (:final texts, :final uses, :final results))
      if (message['role'] == 'assistant') ...[
        if (texts.join().isNotEmpty) {'role': 'assistant', 'content': texts.join()},
        for (final u in uses)
          {
            'type': 'function_call',
            'call_id': u['id'] ?? '',
            'namespace': _namespace,
            'name': u['name'] ?? '',
            'arguments': jsonEncode(u['input'] ?? const <String, Object?>{}),
          },
      ] else ...[
        for (final r in results)
          {
            'type': 'function_call_output',
            'call_id': r['tool_use_id'] ?? '',
            'output': r['content'] ?? '',
          },
        for (final text in texts) {'role': 'user', 'content': text},
      ],
];

/// A final Responses object as Anthropic-style blocks.
AgentResponse fromResponse(Map<String, Object?> response) {
  final blocks = <Block>[
    for (final item in (response['output'] as List? ?? const []).cast<Map<String, Object?>>())
      ...switch (item['type']) {
        'message' => [
          for (final part in (item['content'] as List? ?? const []).cast<Map<String, Object?>>())
            if (part['type'] == 'output_text') {'type': 'text', 'text': part['text']},
        ],
        'function_call' => [
          {
            'type': 'tool_use',
            'id': item['call_id'],
            'name': item['name'],
            'input': parseArguments(item['arguments']),
          },
        ],
        _ => const <Block>[], // reasoning and the like
      },
  ];
  final toolUse = blocks.any((b) => b['type'] == 'tool_use');
  if (!toolUse && response['status'] == 'incomplete') {
    blocks.add(stoppedEarly((response['incomplete_details'] as Map?)?['reason']));
  }
  return AgentResponse(blocks, toolUse ? 'tool_use' : 'end_turn');
}

/// The models the signed-in plan can use (their slugs), as ChatGPT lists them.
Future<List<String>> listChatGptModels(BearerToken token, {http.Client? client}) async {
  final answer = await _send(client ?? http.Client(), token, 'GET', '$_api/models');
  return switch (_json(await answer.stream.bytesToString())) {
    {'models': final List<Object?> models} => [
      for (final m in models.whereType<Map<Object?, Object?>>())
        if (m['visibility'] == 'list') '${m['slug']}',
    ],
    _ => [],
  };
}
