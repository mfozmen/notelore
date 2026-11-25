/// multilingual-e5-small on onnxruntime's C API over FFI (#929). The app finds
/// onnxruntime in the library sherpa-onnx ships (Android, Windows) or in the
/// one it downloads (macOS, where sherpa links it in without exporting it).
///
/// Native code `dart test` cannot load: left out of the coverage gate and kept
/// to the calls; the tokenizer and the pooling around it are in `meaning.dart`.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'meaning.dart';

/// The model file and the tokenizer of multilingual-e5-small in a folder.
const e5Model = 'model_quantized.onnx';
const e5Tokenizer = 'tokenizer.json';

// coverage:ignore-start

/// onnxruntime: [path] when given, else the library the app ships by name.
DynamicLibrary openOnnxRuntime([String? path]) =>
    DynamicLibrary.open(path ?? (Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so'));

/// e5 from the files in [dir], on [ort], with [threads] threads.
Embedder loadE5(String dir, DynamicLibrary ort, {int threads = 2}) {
  final tokenizer = Unigram.fromJson(File(p.join(dir, e5Tokenizer)).readAsStringSync());
  return Embedder(tokenizer.encode, _Session(ort, p.join(dir, e5Model), threads).run);
}

// Places in the OrtApi table of function pointers (onnxruntime_c_api.h). The
// table only grows, so these hold for every version from API 1 on.
const _getErrorMessage = 2;
const _createEnv = 3;
const _createSession = 7;
const _run = 9;
const _createSessionOptions = 10;
const _setIntraOpNumThreads = 24;
const _setInterOpNumThreads = 25;
const _createTensorWithData = 49;
const _getTensorMutableData = 51;
const _createCpuMemoryInfo = 69;
const _releaseStatus = 93;
const _releaseValue = 96;

/// The oldest API with everything used here; any newer library answers it.
const _apiVersion = 14;
const _int64 = 7; // ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64
const _dim = 384;

typedef _P = Pointer<Void>;
typedef _Out = Pointer<Pointer<Void>>;
typedef _Names = Pointer<Pointer<Utf8>>;

final class _ApiBase extends Struct {
  external Pointer<NativeFunction<Pointer<Pointer<Void>> Function(Uint32)>> getApi;
}

class _Session {
  _Session(DynamicLibrary ort, String model, int threads) {
    final base = ort.lookupFunction<Pointer<_ApiBase> Function(), Pointer<_ApiBase> Function()>(
      'OrtGetApiBase',
    )();
    _api = base.ref.getApi.asFunction<Pointer<Pointer<Void>> Function(int)>()(_apiVersion);
    if (_api == nullptr) throw StateError('onnxruntime is older than API $_apiVersion');
    using((arena) {
      final out = arena<Pointer<Void>>();
      _check(
        _at<NativeFunction<_P Function(Int32, Pointer<Utf8>, _Out)>>(_createEnv)
            .asFunction<_P Function(int, Pointer<Utf8>, _Out)>()(
          3, // ORT_LOGGING_LEVEL_ERROR
          'notelore'.toNativeUtf8(allocator: arena),
          out,
        ),
      );
      _env = out.value;
      _check(
        _at<NativeFunction<_P Function(_Out)>>(_createSessionOptions)
            .asFunction<_P Function(_Out)>()(out),
      );
      final options = out.value;
      final setThreads = [_setIntraOpNumThreads, _setInterOpNumThreads];
      for (final at in setThreads) {
        _check(
          _at<NativeFunction<_P Function(_P, Int32)>>(at).asFunction<_P Function(_P, int)>()(
            options,
            at == _setIntraOpNumThreads ? threads : 1,
          ),
        );
      }
      // ORTCHAR_T is wchar_t (UTF-16) on Windows, char (UTF-8) elsewhere.
      final _P path = Platform.isWindows
          ? model.toNativeUtf16(allocator: arena).cast()
          : model.toNativeUtf8(allocator: arena).cast();
      _check(
        _at<NativeFunction<_P Function(_P, _P, _P, _Out)>>(_createSession)
            .asFunction<_P Function(_P, _P, _P, _Out)>()(_env, path, options, out),
      );
      _session = out.value;
      _check(
        _at<NativeFunction<_P Function(Int32, Int32, _Out)>>(
          _createCpuMemoryInfo,
        ).asFunction<_P Function(int, int, _Out)>()(0, 0, out), // device allocator, default memory
      );
      _memory = out.value;
    });
  }

  // Never released: one session lives as long as the isolate that runs it.
  late final Pointer<Pointer<Void>> _api;
  late final _P _env;
  late final _P _session;
  late final _P _memory;

  /// The model's last hidden state for [ids], one sequence.
  Float32List run(List<int> ids) => using((arena) {
    final n = ids.length;
    final shape = arena<Int64>(2)
      ..[0] = 1
      ..[1] = n;
    final inputs = [ids, List.filled(n, 1), List.filled(n, 0)];
    final names = ['input_ids', 'attention_mask', 'token_type_ids'];
    final inputNames = arena<Pointer<Utf8>>(3);
    final values = arena<Pointer<Void>>(3);
    final out = arena<Pointer<Void>>();
    final made = <_P>[];
    final createTensor =
        _at<NativeFunction<_P Function(_P, _P, Size, Pointer<Int64>, Size, Int32, _Out)>>(
          _createTensorWithData,
        ).asFunction<_P Function(_P, _P, int, Pointer<Int64>, int, int, _Out)>();
    try {
      for (var i = 0; i < 3; i++) {
        inputNames[i] = names[i].toNativeUtf8(allocator: arena);
        final buffer = arena<Int64>(n);
        for (var t = 0; t < n; t++) {
          buffer[t] = inputs[i][t];
        }
        _check(createTensor(_memory, buffer.cast(), n * 8, shape, 2, _int64, out));
        made.add(values[i] = out.value);
      }
      final outputName = arena<Pointer<Utf8>>()
        ..value = 'last_hidden_state'.toNativeUtf8(allocator: arena);
      out.value = nullptr;
      _check(
        _at<NativeFunction<_P Function(_P, _P, _Names, _Out, Size, _Names, Size, _Out)>>(_run)
            .asFunction<_P Function(_P, _P, _Names, _Out, int, _Names, int, _Out)>()(
          _session,
          nullptr,
          inputNames,
          values,
          3,
          outputName,
          1,
          out,
        ),
      );
      made.add(out.value);
      final state = arena<Pointer<Void>>();
      _check(
        _at<NativeFunction<_P Function(_P, _Out)>>(_getTensorMutableData)
            .asFunction<_P Function(_P, _Out)>()(out.value, state),
      );
      return Float32List.fromList(state.value.cast<Float>().asTypedList(n * _dim));
    } finally {
      final release = _at<NativeFunction<Void Function(_P)>>(_releaseValue)
          .asFunction<void Function(_P)>();
      made.forEach(release);
    }
  });

  Pointer<T> _at<T extends NativeType>(int index) => _api[index].cast<T>();

  void _check(_P status) {
    if (status == nullptr) return;
    final message = _at<NativeFunction<Pointer<Utf8> Function(_P)>>(_getErrorMessage)
        .asFunction<Pointer<Utf8> Function(_P)>()(status)
        .toDartString();
    _at<NativeFunction<Void Function(_P)>>(_releaseStatus).asFunction<void Function(_P)>()(status);
    throw StateError('onnxruntime: $message');
  }
}

// coverage:ignore-end
