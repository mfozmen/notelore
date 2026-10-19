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

/// The model in the file at [path], loaded on its first turn (a few seconds)
/// and kept for the next ones, which reuse its cached prompt.
LocalEngine nativeDeviceEngine(String path) => _LlamaDart(path);

class _LlamaDart implements LocalEngine {
  _LlamaDart(this.path);

  final String path;
  Future<LlamaEngine>? _loading;

  Future<LlamaEngine> _engine() => _loading ??= () async {
    try {
      // The whole prompt with the tools is ~2,800 tokens; a turn adds tool results.
      return await LlamaEngine.load(
        LlamaModel(ModelSource.path(path)),
        params: const ModelParams(contextSize: 8192),
      );
    } on Object catch (error) {
      _loading = null; // tried again on the next turn
      throw LocalModelFailed('$error');
    }
  }();

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
  Future<void> dispose() async {
    final loading = _loading;
    _loading = null;
    if (loading == null) return;
    try {
      await (await loading).dispose();
    } on LocalModelFailed {
      return; // it never loaded
    }
  }
}

// coverage:ignore-end
