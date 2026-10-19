import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory Google Drive speaking the slice of the v3 REST API the client
/// uses: My Drive, where every file was created through it (the drive.file
/// scope), and the hidden app folder (appDataFolder, drive.appdata).
class FakeDrive {
  final files = <String, Map<String, Object?>>{}; // id -> metadata incl. 'data'
  var token = 'token-1'; // the access token it accepts
  var offline = false;
  var pageSize = 1000; // the largest page it hands out

  /// False for a grant from before the app folder (#454): drive.file only.
  var appData = true;
  final requests = <String>[];
  var _next = 0;

  late final client = MockClient(_handle);

  String _id() => 'f${++_next}';

  /// The app folder's live file named [path], e.g. "projects/a.md".
  Map<String, Object?>? file(String path) => files.values
      .where((f) => f['space'] == _app && f['name'] == path && !_removed(f))
      .firstOrNull;

  /// The text of the app folder's live file named [path].
  String? text(String path) {
    final found = file(path);
    return found == null ? null : utf8.decode(found['data']! as List<int>);
  }

  static bool _removed(Map<String, Object?> file) =>
      (file['appProperties'] as Map?)?['removed'] != null;

  /// Puts a file there as another device or the Drive web UI would.
  Map<String, Object?> add(String name, String parent, {String? text, bool folder = false}) {
    final id = _id();
    return files[id] = {
      'id': id,
      'name': name,
      'parents': [parent],
      'space': parent == _app ? _app : 'drive',
      'mimeType': folder ? 'application/vnd.google-apps.folder' : 'text/markdown',
      'trashed': false,
      'modifiedTime': '2026-10-01T00:00:${_next.toString().padLeft(2, '0')}Z',
      if (text != null) 'data': utf8.encode(text),
    };
  }

  /// The visible "Notelore" folder in My Drive the notes lived in before
  /// #454, holding [notes] by path.
  Map<String, Object?> legacy(Map<String, String> notes) {
    final root = add('Notelore', 'root', folder: true)..['appProperties'] = {'notelore': 'root'};
    for (final MapEntry(key: path, value: text) in notes.entries) {
      var parent = root['id']! as String;
      final names = path.split('/');
      for (final name in names.take(names.length - 1)) {
        final existing = files.values
            .where((f) => f['name'] == name && (f['parents']! as List).contains(parent))
            .firstOrNull;
        parent = (existing ?? add(name, parent, folder: true))['id']! as String;
      }
      add(names.last, parent, text: text);
    }
    return root;
  }

  Map<String, Object?> _public(Map<String, Object?> file) => {
    for (final MapEntry(:key, :value) in file.entries)
      if (key != 'data' && key != 'trashed' && key != 'space') key: value,
    if (file['data'] case final List<int> data) 'md5Checksum': md5.convert(data).toString(),
  };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  http.Response _error(String message, int status) => _json({
    'error': {'message': message},
  }, status);

  Future<http.Response> _handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (offline) throw http.ClientException('offline');
    if (request.headers['Authorization'] != 'Bearer $token') {
      return _error('Invalid Credentials', 401);
    }
    final path = request.url.path;
    final query = request.url.queryParameters;
    final segments = request.url.pathSegments;
    final id = segments.last == 'files' ? null : segments.last;
    final file = files[id];
    final inApp =
        query['spaces'] == _app ||
        file?['space'] == _app ||
        (request.method == 'POST' && latin1.decode(request.bodyBytes).contains('"$_app"'));
    if (inApp && !appData) {
      return _error('Request had insufficient authentication scopes.', 403);
    }
    if (request.method == 'GET' && id == null) return _list(query);
    if (id != null && (file == null || file['trashed'] == true)) {
      return _error('File not found: $id', 404);
    }
    switch (request.method) {
      case 'GET':
        return http.Response.bytes(file!['data']! as List<int>, 200);
      case 'DELETE':
        files.remove(id);
        return http.Response('', 204);
      case 'POST' when path.startsWith('/upload/'):
        return _created(_multipart(request));
      case 'POST':
        return _created((jsonDecode(request.body) as Map).cast<String, Object?>());
      case 'PATCH' when path.startsWith('/upload/'):
        file!['data'] = request.bodyBytes;
        file['modifiedTime'] = '2026-10-02T00:00:${(++_next).toString().padLeft(2, '0')}Z';
        return _json(_public(file));
      default: // PATCH metadata: trashing, or marking
        final change = (jsonDecode(request.body) as Map).cast<String, Object?>();
        if (change['trashed'] == true && file!['space'] == _app) {
          return _error('Files within the Application Data folder cannot be trashed.', 403);
        }
        if (change.remove('appProperties') case final Map<String, Object?> marks) {
          file!['appProperties'] = {...?(file['appProperties'] as Map?), ...marks};
        }
        file!.addAll(change);
        return _json(_public(file));
    }
  }

  http.Response _list(Map<String, String> query) {
    if (query['q'] != 'trashed = false') return _json({'error': 'unexpected query'}, 400);
    final space = query['spaces'] ?? 'drive';
    final all = files.values.where((f) => f['trashed'] != true && f['space'] == space).toList();
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

  http.Response _created(Map<String, Object?> metadata) {
    final id = _id();
    final file = files[id] = {
      ...metadata,
      'id': id,
      'trashed': false,
      'space': (metadata['parents'] as List?)?.contains(_app) ?? false ? _app : 'drive',
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

const _app = 'appDataFolder';
