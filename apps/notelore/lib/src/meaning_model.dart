/// The model that finds notes by meaning (#929): multilingual-e5-small (MIT),
/// downloaded by itself after setup like Whisper, each file checked against
/// its SHA-256. macOS also gets onnxruntime, which sherpa-onnx links in there
/// without exporting it; Android and Windows use the library sherpa-onnx ships.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'whisper_model.dart';

const _e5 =
    'https://huggingface.co/Xenova/multilingual-e5-small/resolve/761b726dd34fb83930e26aab4e9ac3899aa1fa78';

/// onnxruntime's own Python wheel for macOS (both architectures), from PyPI.
const ortWheel = 'onnxruntime-1.22.1-macos.whl';
const _ortInWheel = 'onnxruntime/capi/libonnxruntime.1.22.1.dylib';
const _ortLibrary = 'libonnxruntime.dylib';

const _files = [
  ModelFile(
    'model_quantized.onnx',
    '$_e5/onnx/model_quantized.onnx',
    'f80102d3f2a1229f387d3c81909990d8945513e347b0eab049f7de3c6f98c193',
    118308185,
  ),
  ModelFile(
    'tokenizer.json',
    '$_e5/tokenizer.json',
    '0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39',
    17082730,
  ),
];

const _ort = ModelFile(
  ortWheel,
  'https://files.pythonhosted.org/packages/48/70/ca2a4d38a5deccd98caa145581becb20c53684f451e89eb3a39915620066/onnxruntime-1.22.1-cp312-cp312-macosx_13_0_universal2.whl',
  'a938d11c0dc811badf78e435daa3899d9af38abee950d87f3ab7430eb5b3cf5a',
  34342883,
);

/// What this device downloads.
List<ModelFile> meaningFilesFor({required bool macOS}) => [..._files, if (macOS) _ort];

/// The onnxruntime library to load from [dir]: taken out of a downloaded
/// wheel the first time; null where the app ships its own.
String? ortLibrary(String dir) {
  final library = p.join(dir, _ortLibrary);
  if (File(library).existsSync()) return library;
  final wheel = File(p.join(dir, ortWheel));
  if (!wheel.existsSync()) return null;
  final entry = ZipDecoder().decodeBytes(wheel.readAsBytesSync()).findFile(_ortInWheel);
  if (entry == null) return null;
  // Written aside, then renamed: a half-written library is never loaded.
  File('$library.part')
    ..writeAsBytesSync(Uint8List.fromList(entry.content as List<int>))
    ..renameSync(library);
  return library;
}

/// The e5 model as the session uses it, off the screen's thread.
abstract interface class MeaningModel {
  /// One vector per note text.
  Future<List<Float32List>> passages(List<String> texts);

  /// The vector for a message.
  Future<Float32List> query(String text);
}
