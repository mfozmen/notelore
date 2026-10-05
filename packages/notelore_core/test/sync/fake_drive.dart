import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory Google Drive speaking the slice of the v3 REST API the client
/// uses. Every file it holds was created through it, like the drive.file scope.
class FakeDrive {
  final files = <String, Map<String, Object?>>{}; // id -> metadata incl. 'data'
  var token = 'token-1'; // the access token it accepts
  var offline = false;
  var pageSize = 1000; // the largest page it hands out
  final requests = <String>[];
  var _next = 0;

  late final client = MockClient(_handle);

  String _id() => 'f${++_next}';

  /// The text of the file at [path] under the Notelore folder, e.g. "projects/a.md".
  String? text(String path) {
    final file = _byPath(path);
    return file == null ? null : utf8.decode(file['data']! as List<int>);
  }

  Map<String, Object?>? _byPath(String path) {
    String? parent = files.values
        .where((f) => f['name'] == 'Notelore' && f['trashed'] != true)
        .map((f) => f['id']! as String)
        .firstOrNull;
    Map<String, Object?>? found;
    for (final name in path.split('/')) {
      found = files.values
          .where(
            (f) =>
                f['name'] == name &&
                (f['parents']! as List).contains(parent) &&
                f['trashed'] != true,
          )
          .firstOrNull;
      if (found == null) return null;
      parent = found['id']! as String;
    }
    return found;
  }

  /// Puts a file there as another device or the Drive web UI would.
  Map<String, Object?> add(String name, String parent, {String? text, bool folder = false}) {
    final id = _id();
    return files[id] = {
      'id': id,
      'name': name,
      'parents': [parent],
      'mimeType': folder ? 'application/vnd.google-apps.folder' : 'text/markdown',
      'trashed': false,
      'modifiedTime': '2026-10-01T00:00:${_next.toString().padLeft(2, '0')}Z',
      if (text != null) 'data': utf8.encode(text),
    };
  }

  Map<String, Object?> _public(Map<String, Object?> file) => {
    for (final MapEntry(:key, :value) in file.entries)
      if (key != 'data' && key != 'trashed') key: value,
    if (file['data'] case final List<int> data) 'md5Checksum': md5.convert(data).toString(),
  };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Future<http.Response> _handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (offline) throw http.ClientException('offline');
    if (request.headers['Authorization'] != 'Bearer $token') {
      return _json({
        'error': {'message': 'Invalid Credentials'},
      }, 401);
    }
    final path = request.url.path;
    final query = request.url.queryParameters;
    final segments = request.url.pathSegments;
    final id = segments.last == 'files' ? null : segments.last;
    if (request.method == 'GET' && id == null) return _list(query);
    final file = files[id];
    if (id != null && (file == null || file['trashed'] == true)) {
      return _json({
        'error': {'message': 'File not found: $id'},
      }, 404);
    }
    switch (request.method) {
      case 'GET':
        return http.Response.bytes(file!['data']! as List<int>, 200);
      case 'POST' when path.startsWith('/upload/'):
        return _created(_multipart(request), request);
      case 'POST':
        return _created((jsonDecode(request.body) as Map).cast<String, Object?>(), request);
      case 'PATCH' when path.startsWith('/upload/'):
        file!['data'] = request.bodyBytes;
        file['modifiedTime'] = '2026-10-02T00:00:${(++_next).toString().padLeft(2, '0')}Z';
        return _json(_public(file));
      default: // PATCH metadata: trashing
        file!.addAll((jsonDecode(request.body) as Map).cast<String, Object?>());
        return _json(_public(file));
    }
  }

  http.Response _list(Map<String, String> query) {
    if (query['q'] != 'trashed = false') return _json({'error': 'unexpected query'}, 400);
    final all = files.values.where((f) => f['trashed'] != true).toList();
    final start = int.parse(query['pageToken'] ?? '0');
    final size = pageSize < int.parse(query['pageSize']!)
        ? pageSize
        : int.parse(query['pageSize']!);
    final page = all.skip(start).take(size).map(_public).toList();
    return _json({
      'files': page,
      if (start + size < all.length) 'nextPageToken': '${start + size}',
    });
  }

  http.Response _created(Map<String, Object?> metadata, http.Request request) {
    final id = _id();
    final file = files[id] = {
      ...metadata,
      'id': id,
      'trashed': false,
      'modifiedTime': '2026-10-01T00:00:${_next.toString().padLeft(2, '0')}Z',
    };
    return _json(_public(file));
  }

  /// metadata JSON plus content from a multipart/related upload.
  Map<String, Object?> _multipart(http.Request request) {
    final boundary = request.headers['Content-Type']!.split('boundary=').last;
    final parts = latin1.decode(request.bodyBytes).split('--$boundary');
    String body(String part) => part.substring(part.indexOf('\r\n\r\n') + 4, part.length - 2);
    final metadata = (jsonDecode(body(parts[1])) as Map).cast<String, Object?>();
    return {...metadata, 'data': latin1.encode(body(parts[2]))};
  }
}
