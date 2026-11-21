/// e5 in a background isolate over onnxruntime (#929), so neither embedding
/// the notes nor a message ever holds up the screen. Native code `flutter test`
/// cannot load: left out of the coverage gate and kept thin; the model's
/// arithmetic is in notelore_core's `meaning.dart`, fully tested.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:notelore_core/notelore_core.dart' show Embedder, loadE5, openOnnxRuntime;
import 'package:path/path.dart' as p;

import 'meaning_model.dart';

// coverage:ignore-start

/// e5 from [dir], on onnxruntime at [library] or the one the app ships.
MeaningModel nativeMeaning(String dir, String? library) => _IsolateMeaning(
  dir,
  // By its full path on Windows: a bare name would also find System32's copy.
  library ??
      (Platform.isWindows
          ? p.join(p.dirname(Platform.resolvedExecutable), 'onnxruntime.dll')
          : null),
);

class _IsolateMeaning implements MeaningModel {
  _IsolateMeaning(this.dir, this.library);

  final String dir;
  final String? library;
  Future<SendPort>? _worker;

  @override
  Future<List<Float32List>> passages(List<String> texts) async =>
      (await _ask(true, texts)).cast<Float32List>();

  @override
  Future<Float32List> query(String text) async => (await _ask(false, [text])).single as Float32List;

  Future<List<Object?>> _ask(bool passages, List<String> texts) async {
    final worker = await (_worker ??= _start());
    final reply = ReceivePort();
    worker.send((passages, texts, reply.sendPort));
    final (ok, answer) = await reply.first as (bool, Object?);
    reply.close();
    if (!ok) throw StateError('$answer');
    return answer! as List<Object?>;
  }

  Future<SendPort> _start() async {
    final ready = ReceivePort();
    await Isolate.spawn(_work, (ready.sendPort, dir, library));
    final (ok, answer) = await ready.first as (bool, Object?);
    if (!ok) {
      _worker = null; // the next ask tries again
      throw StateError('$answer');
    }
    return answer! as SendPort;
  }
}

void _work((SendPort, String, String?) start) {
  final (ready, dir, library) = start;
  final Embedder e5;
  try {
    e5 = loadE5(dir, openOnnxRuntime(library));
  } on Object catch (error) {
    ready.send((false, '$error'));
    return;
  }
  final inbox = ReceivePort();
  ready.send((true, inbox.sendPort));
  inbox.listen((message) {
    final (passages, texts, reply) = message as (bool, List<String>, SendPort);
    try {
      reply.send((true, [for (final t in texts) passages ? e5.passage(t) : e5.query(t)]));
    } on Object catch (error) {
      reply.send((false, '$error'));
    }
  });
}

// coverage:ignore-end
