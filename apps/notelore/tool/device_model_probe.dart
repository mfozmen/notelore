/// Measures the model on the device (#328) on an Android emulator or phone:
/// load time, prefill and decode speed, and memory, for Notelore's real
/// system prompt and tools, a cold turn and then a warm one that reuses the
/// cached prompt. It reads only the GGUF named by --dart-define=MODEL and
/// opens no app state, keys or notes.
///
///     adb -s emulator-5554 push model.gguf /data/local/tmp/model.gguf
///     flutter run -d emulator-5554 --profile -t tool/device_model_probe.dart \
///       --dart-define=MODEL=/data/local/tmp/model.gguf
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:llamadart/llamadart.dart';
import 'package:notelore/src/device_model.dart';
import 'package:notelore_core/notelore_core.dart';

const _model = String.fromEnvironment('MODEL', defaultValue: '/data/local/tmp/model.gguf');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Running the device model probe; see Flutter logs.')),
    ),
  );
  String mb(int bytes) => '${(bytes / 1e6).round()} MB';
  print(
    'probe: model $_model, ${mb(File(_model).lengthSync())}; rss ${mb(ProcessInfo.currentRss)}',
  );

  final load = Stopwatch()..start();
  final engine = await LlamaEngine.load(
    LlamaModel(ModelSource.path(_model)),
    params: const ModelParams(contextSize: 8192),
  );
  print('probe: load ${load.elapsedMilliseconds} ms; rss ${mb(ProcessInfo.currentRss)}');
  print('probe: sampling ${describeSampling(deviceSampling)}');

  final tools = toolsFor([
    for (final tool in noteTools)
      {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.inputSchema,
        },
      },
  ]);
  final messages = [
    {'role': 'system', 'content': systemPrompt()},
    {'role': 'user', 'content': 'Mopsos: the hit rate is calculated weekly, on Sundays.'},
  ];
  Future<void> turn(String name, List<Map<String, Object?>> history) async {
    final watch = Stopwatch()..start();
    final completion = await engine.complete(
      toLlama(history),
      params: deviceSampling,
      tools: tools,
    );
    final total = watch.elapsedMilliseconds;
    final usage = completion.usage;
    final first = usage?.timeToFirstToken?.inMilliseconds;
    final prompt = usage?.promptTokens ?? 0;
    final cached = usage?.cachedPromptTokens ?? 0;
    final out = usage?.completionTokens ?? 0;
    String rate(int tokens, int? ms) =>
        ms == null || ms <= 0 ? '?' : (tokens * 1000 / ms).toStringAsFixed(1);
    print(
      'probe: $name: $total ms; prompt $prompt tokens ($cached cached), '
      'first token after ${first ?? '?'} ms (${rate(prompt - cached, first)} tok/s prefill), '
      '$out out (${rate(out, first == null ? null : total - first)} tok/s decode); '
      'calls ${completion.toolCalls.map((c) => c.name).toList()}; rss ${mb(ProcessInfo.currentRss)}',
    );
  }

  await turn('cold', messages);
  await turn('warm', [
    ...messages,
    {'role': 'assistant', 'content': 'Saved to Mopsos.'},
    {'role': 'user', 'content': 'And the database is SQLite.'},
  ]);
  await engine.dispose();
  print('probe: complete; max rss ${mb(ProcessInfo.maxRss)}');
}
