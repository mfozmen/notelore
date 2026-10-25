/// llama.cpp through llamadart (#328): the native load and generation that
/// `flutter test` cannot run. Kept thin; the turn's conversion is in
/// device_model.dart, tested, and the provider around it in the core.
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:notelore_core/notelore_core.dart';

import 'device_model.dart';

// coverage:ignore-start
/// The kernel's memory figures on Android (`/proc/meminfo`), or null.
String? readMeminfo() {
  try {
    return File('/proc/meminfo').readAsStringSync();
  } on FileSystemException {
    return null; // then the model is not offered
  }
}

/// The phone's fast cores from the kernel's per-CPU peak frequencies, or 0
/// (llama.cpp's automatic choice) where they are not readable.
int _deviceThreads() {
  if (!Platform.isAndroid) return 0;
  final frequencies = <int>[];
  for (var cpu = 0; cpu < Platform.numberOfProcessors; cpu++) {
    try {
      frequencies.add(
        int.parse(
          File('/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq')
              .readAsStringSync()
              .trim(),
        ),
      );
    } on FileSystemException {
      // Offline, or hidden by the kernel: this core's cluster leaves no vote.
    } on FormatException {
      // Not a frequency: same.
    }
  }
  return fastCores(frequencies, fallback: 0);
}

/// The model in the file at [path], loaded on its first turn (a few seconds)
/// and kept for the next ones, which reuse its cached prompt.
LocalEngine nativeDeviceEngine(String path) => _LlamaDart(path);

class _LlamaDart implements LocalEngine {
  _LlamaDart(this.path);

  final String path;
  Future<LlamaEngine>? _loading;

  /// The previous engine's release: a new one loads only once it is done, so
  /// a quick switch away and back never holds two copies of the model.
  static Future<void> _released = Future.value();

  Future<LlamaEngine> _engine() => _loading ??= () async {
    await _released;
    final threads = _deviceThreads();
    try {
      // The whole prompt with the tools is ~2,800 tokens; a turn adds tool results.
      return await LlamaEngine.load(
        LlamaModel(ModelSource.path(path)),
        params: ModelParams(
          contextSize: 8192,
          numberOfThreads: threads,
          numberOfThreadsBatch: threads,
        ),
      );
    } on Object catch (error) {
      _loading = null; // tried again on the next turn
      throw LocalModelFailed('$error');
    }
  }();

  @override
  Future<void> prefill(String system, List<Map<String, Object?>> tools) async {
    final engine = await _engine();
    try {
      // maxTokens 0 evaluates the prompt and stops before generating a token.
      await engine
          .create(
            [LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system)],
            params: const GenerationParams(maxTokens: 0),
            tools: tools.isEmpty ? null : toolsFor(tools),
          )
          .drain<void>();
    } on Object catch (error) {
      throw LocalModelFailed('$error');
    }
  }

  @override
  Future<Map<String, Object?>> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
  ) async {
    final engine = await _engine();
    try {
      final completion = await engine.complete(
        toLlama(messages),
        tools: tools.isEmpty ? null : toolsFor(tools),
      );
      return fromLlama(completion);
    } on Object catch (error) {
      // A context past its size, a runtime error: said in the chat, not a crash.
      throw LocalModelFailed('$error');
    }
  }

  @override
  Future<void> dispose() {
    final loading = _loading;
    _loading = null;
    if (loading == null) return Future.value();
    // Chained: every release done before the next engine loads.
    return _released = _released.then((_) async {
      try {
        await (await loading).dispose();
      } on Object {
        return; // never loaded, or failed to let go: nothing more to free here
      }
    });
  }
}

// coverage:ignore-end
