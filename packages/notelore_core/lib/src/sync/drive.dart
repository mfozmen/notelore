/// Google Drive as the sync [Remote], over the Drive v3 REST API.
///
/// The notes tree is mirrored under one `Notelore` folder in My Drive (folders
/// for `projects/`, `topics/`, `_archive/`...), so the backup is browsable in
/// Drive too. The scope is `drive.file`: the app only ever sees files it
/// created, so one listing of everything it can see is the whole tree.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../providers/http.dart';
import 'engine.dart';

const driveScope = 'https://www.googleapis.com/auth/drive.file';

const _files = 'https://www.googleapis.com/drive/v3/files';
const _uploads = 'https://www.googleapis.com/upload/drive/v3/files';
const _folderType = 'application/vnd.google-apps.folder';
const _fields = 'id,name,parents,mimeType,md5Checksum,modifiedTime,appProperties';
const _rootName = 'Notelore';
const _rootMark = {'notelore': 'root'};

/// A valid access token; [refresh] asks for a new one after the old one was refused.
typedef AccessToken = Future<String> Function({bool refresh});

class DriveRemote implements Remote {
  DriveRemote(this._client, this._token, {this.timeout = const Duration(seconds: 60)});

  /// How long one request may take before the sync counts as offline.
  final Duration timeout;

  final http.Client _client;
  final AccessToken _token;

  /// Folder ids by path relative to the notes root ('' is the Notelore folder),
  /// learned from [list] and from the folders this client creates.
  final _folders = <String, String>{};

  Future<http.Response> _send(
    String method,
    String url, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    for (var refresh = false; ; refresh = true) {
      final request = http.Request(method, Uri.parse(url).replace(queryParameters: query))
        ..headers.addAll({...headers, 'Authorization': 'Bearer ${await _token(refresh: refresh)}'});
      if (body != null) request.bodyBytes = body;
      final http.Response response;
      try {
        response = await _client.send(request).then(http.Response.fromStream).timeout(timeout);
      } on http.ClientException catch (error) {
        throw NetworkError(error.message);
      } on TimeoutException {
        throw const NetworkError('Google Drive did not answer in time');
      }
      if (response.statusCode == 401 && !refresh) continue; // expired: refresh once
      if (response.statusCode >= 400) {
        throw HttpError(response.statusCode, errorMessage(utf8.decode(response.bodyBytes)));
      }
      return response;
    }
  }

  Future<Map<String, Object?>> _json(
    String method,
    String url, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    final response = await _send(
      method,
      url,
      query: {'fields': _fields, ...query},
      headers: {if (body != null) 'Content-Type': 'application/json; charset=UTF-8'},
      body: body == null ? null : utf8.encode(jsonEncode(body)),
    );
    return (jsonDecode(utf8.decode(response.bodyBytes)) as Map).cast<String, Object?>();
  }

  static RemoteFile _remoteFile(Map<String, Object?> file) => RemoteFile(
    id: file['id']! as String,
    md5: file['md5Checksum']! as String,
    modified: file['modifiedTime']! as String,
  );

  @override
  Future<Map<String, RemoteFile>> list() async {
    final all = <Map<String, Object?>>[];
    String? page;
    do {
      final answer = await _json(
        'GET',
        _files,
        query: {
          'q': 'trashed = false',
          'orderBy': 'createdTime',
          'pageSize': '1000',
          'fields': 'nextPageToken,files($_fields)',
          'pageToken': ?page,
        },
      );
      all.addAll((answer['files']! as List).cast<Map<String, Object?>>());
      page = answer['nextPageToken'] as String?;
    } while (page != null);

    final byId = {for (final file in all) file['id']! as String: file};
    // Two devices may each have created a Notelore folder before either synced:
    // the oldest one wins (the listing is in creation order).
    final root = all
        .where((f) => f['mimeType'] == _folderType && f['name'] == _rootName)
        .where((f) => (f['appProperties'] as Map?)?['notelore'] == 'root')
        .firstOrNull;
    _folders.clear();
    if (root == null) return {};

    /// The path of [file] under the root, or null when it lies outside it.
    String? pathOf(Map<String, Object?> file) {
      final names = <String>[];
      var current = file;
      for (var depth = 0; depth < 64; depth++) {
        names.add('${current['name']}');
        final parent = (current['parents'] as List?)?.first as String?;
        if (parent == root['id']) return names.reversed.join('/');
        final next = byId[parent];
        if (next == null) return null;
        current = next;
      }
      return null; // a parent cycle or an absurd depth: not ours
    }

    _folders[''] = root['id']! as String;
    final notes = <String, RemoteFile>{};
    for (final file in all) {
      final path = file == root ? null : pathOf(file);
      if (path == null) continue;
      if (file['mimeType'] == _folderType) {
        _folders[path] = file['id']! as String;
      } else if (file['md5Checksum'] != null) {
        notes[path] = _remoteFile(file); // Google Docs have no content hash: not notes
      }
    }
    return notes;
  }

  @override
  Future<List<int>> download(String fileId) async =>
      (await _send('GET', '$_files/$fileId', query: {'alt': 'media'})).bodyBytes;

  @override
  Future<RemoteFile> upload(String rel, List<int> data, String? fileId) async {
    if (fileId != null) {
      final response = await _send(
        'PATCH',
        '$_uploads/$fileId',
        query: {'uploadType': 'media', 'fields': _fields},
        headers: {'Content-Type': 'text/markdown'},
        body: data,
      );
      return _remoteFile((jsonDecode(utf8.decode(response.bodyBytes)) as Map).cast());
    }
    final slash = rel.lastIndexOf('/');
    final parent = await _folder(slash < 0 ? '' : rel.substring(0, slash));
    final metadata = jsonEncode({
      'name': rel.substring(slash + 1),
      'parents': [parent],
      'mimeType': 'text/markdown',
    });
    const boundary = 'notelore-part-boundary';
    final body = [
      ...utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n'
        '--$boundary\r\nContent-Type: text/markdown\r\n\r\n',
      ),
      ...data,
      ...utf8.encode('\r\n--$boundary--'),
    ];
    final response = await _send(
      'POST',
      _uploads,
      query: {'uploadType': 'multipart', 'fields': _fields},
      headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
      body: body,
    );
    return _remoteFile((jsonDecode(utf8.decode(response.bodyBytes)) as Map).cast());
  }

  /// The id of the folder at [path] under the root, created (with its parents)
  /// when missing.
  Future<String> _folder(String path) async {
    if (_folders[path] case final id?) return id;
    final String parent;
    final Map<String, Object?> metadata;
    if (path.isEmpty) {
      parent = 'root'; // My Drive
      metadata = {'name': _rootName, 'appProperties': _rootMark};
    } else {
      final slash = path.lastIndexOf('/');
      parent = await _folder(slash < 0 ? '' : path.substring(0, slash));
      metadata = {'name': path.substring(slash + 1)};
    }
    final created = await _json(
      'POST',
      _files,
      body: {
        ...metadata,
        'mimeType': _folderType,
        'parents': [parent],
      },
    );
    return _folders[path] = created['id']! as String;
  }

  @override
  Future<void> trash(String fileId) async {
    await _json('PATCH', '$_files/$fileId', body: {'trashed': true});
  }
}
