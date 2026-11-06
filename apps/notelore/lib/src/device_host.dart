/// The chat model that runs on this device (#328), split out of [Session]
/// (#659): the one engine every rebuilt provider shares, the prefill of its
/// fixed prompt (#595), and its download.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:notelore_core/notelore_core.dart';

import 'whisper_model.dart';

class DeviceModelHost extends ChangeNotifier {
  DeviceModelHost({
    required this.model,
    required this.file,
    required this.makeEngine,
    required this.exclusive,
    required this.fetch,
  });

  /// The model's files in this device's state, downloaded on request.
  final WhisperModel model;

  /// The model file the engine loads, asked when it loads.
  final String Function() file;
  final LocalEngine Function(String path) makeEngine;

  /// [Session]'s one queue of chat turns and syncs: a prefill waits its turn.
  final Future<T> Function<T>(Future<T> Function() task) exclusive;

  /// [Session]'s download, reporting progress and problems through the two setters.
  final Future<void> Function(
    void Function(double? done) progress,
    void Function(DownloadProblem? why) problem,
  )
  fetch;

  /// The one loaded engine, if any: a rebuilt provider reuses it, never a
  /// second copy of the model in memory.
  LocalEngine? _engine;
  LocalProvider? _provider;

  /// Whether a provider runs on the engine now.
  bool get loaded => _provider != null;

  /// A provider for [chosenModel] on the one engine.
  LocalProvider provider(String chosenModel) {
    final engine = _engine ??= makeEngine(model.path(file()));
    return _provider = LocalProvider(chosenModel, engine);
  }

  /// The engine and prompt+tools already prefilled (#595).
  LocalEngine? _prefilledEngine;
  String? _prefilledKey;
  int _prefillRun = 0;

  bool preparing = false;

  /// Reads [system] and [tools] into the engine's cache before the first
  /// message, so that message only pays for what the user wrote.
  void startPrefill(String system, List<Tool> tools) {
    final provider = _provider;
    final engine = _engine;
    if (provider == null || engine == null) return;
    final key = jsonEncode([
      system.replaceFirst(RegExp(r'\d{2}:\d{2}(?=, local time\.)'), '--:--'),
      for (final tool in tools) [tool.name, tool.description, tool.inputSchema],
    ]);
    if (identical(engine, _prefilledEngine) && key == _prefilledKey) return;
    _prefilledEngine = engine;
    _prefilledKey = key;
    final run = ++_prefillRun;
    preparing = true;
    notifyListeners();
    final ready = Completer<void>();
    // One event: the setup test turn is queued right after connect and must
    // cancel this before it reads a prompt it is about to replace.
    unawaited(Future<void>(ready.complete));
    unawaited(
      exclusive(() async {
        await ready.future;
        if (run == _prefillRun) {
          try {
            await provider.prefill(system, tools);
          } on Exception {
            // The first turn loads the model again and says what went wrong.
          } finally {
            if (run == _prefillRun) {
              preparing = false;
              notifyListeners();
            }
          }
        }
      }),
    );
  }

  /// Another prompt is about to use the engine: a prefill not yet run is dropped.
  void cancelPrefill() {
    _prefillRun++;
    _prefilledEngine = null;
    _prefilledKey = null;
    preparing = false;
    notifyListeners();
  }

  /// Lets go of the model, when another model is used or none.
  Future<void> free() async {
    final engine = _engine;
    _engine = null;
    _provider = null;
    _prefilledEngine = null;
    _prefilledKey = null;
    _prefillRun++;
    preparing = false;
    await engine?.dispose();
  }

  /// From 0 to 1 while the model downloads, else null. Set through [fetch],
  /// which notifies [Session]'s listeners as it does for Whisper.
  double? progress;

  /// Why the last download failed, if it did.
  DownloadProblem? problem;

  /// One download at a time; a second call waits for the one running.
  Future<void> download() => _download ??= fetch(
    (done) => progress = done,
    (why) => problem = why,
  ).whenComplete(() => _download = null);
  Future<void>? _download;

  /// The download running now, if any.
  Future<void>? get downloading => _download;
}
