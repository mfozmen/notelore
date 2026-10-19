/// Google Drive as the sync [Remote], over the Drive v3 REST API.
///
/// The notes are in Drive's hidden app folder (`appDataFolder`, scope
/// `drive.appdata`): Drive shows it nowhere, so a person cannot edit, move or
/// delete a note there by accident (#454). Each file sits directly in it,
/// named by its path relative to the notes root. Drive cannot trash a file
/// there, so a removal marks it (`appProperties.removed`, a UTC time), the
/// listing skips it, and a listing deletes the ones marked over 30 days ago,
/// as Drive empties its trash.
///
/// Before #454 the notes were in a visible `Notelore` folder in My Drive
/// (scope `drive.file`, which only ever sees files the app created). The first
/// listing copies what is still there into the app folder, never a name
/// already there, so a move cut off or made by two devices at once is safe,
/// then moves that folder to Drive's trash.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../oauth.dart';
import '../providers/http.dart';
import 'engine.dart';

/// Both grants: the app folder, and the old visible folder to move out of.
const driveScope =
    'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/drive.appdata';

const _files = 'https://www.googleapis.com/drive/v3/files';
const _uploads = 'https://www.googleapis.com/upload/drive/v3/files';
const _folderType = 'application/vnd.google-apps.folder';
const _fields = 'id,name,parents,mimeType,md5Checksum,modifiedTime,appProperties';
const _app = 'appDataFolder';
const _rootName = 'Notelore';
const _contentType = 'Content-Type';

/// How long a removed file stays, like a file in Drive's trash.
const _kept = Duration(days: 30);

/// A valid access token; [refresh] asks for a new one after the old one was refused.
typedef AccessToken = Future<String> Function({bool refresh});

class DriveRemote implements Remote {
  DriveRemote(
    this._client,
    this._token, {
    this.timeout = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.timestamp;

  /// How long one request may take before the sync counts as offline.
  final Duration timeout;

  final http.Client _client;
  final AccessToken _token;
  final DateTime Function() _clock;

  @override
  var moved = false;
  var _checkedVisible = false;

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
        final message = errorMessage(utf8.decode(response.bodyBytes));
        // A grant from before the app folder: signing in again adds it.
        if (response.statusCode == 403 && message.contains('insufficient authentication scopes')) {
          throw NotSignedIn(message);
        }
        throw HttpError(response.statusCode, message);
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
      headers: {if (body != null) _contentType: 'application/json; charset=UTF-8'},
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
    moved = false;
    if (!_checkedVisible) {
      await _moveVisible();
      _checkedVisible = true;
    }
    final now = _clock().toUtc();
    final notes = <String, RemoteFile>{};
    // In creation order: when two devices copied the same file, the first wins.
    for (final file in await _listAll(_app)) {
      final name = file['name']! as String;
      final removed = (file['appProperties'] as Map?)?['removed'] as String?;
      if (removed != null) {
        final at = DateTime.tryParse(removed);
        if (at == null || now.difference(at) > _kept) await _delete(file['id']! as String);
      } else if (notes.containsKey(name)) {
        await trash(file['id']! as String);
      } else if (file['md5Checksum'] != null) {
        notes[name] = _remoteFile(file); // Google Docs have no content hash: not notes
      }
    }
    return notes;
  }

  /// Copies the visible folder's files into the app folder, those not there
  /// yet, then trashes the folder.
  Future<void> _moveVisible() async {
    final all = await _listAll('drive');
    final byId = {for (final file in all) file['id']! as String: file};
    // Two devices may each have created a Notelore folder before either synced:
    // the oldest one held the notes (the listing is in creation order).
    final root = all
        .where((f) => f['mimeType'] == _folderType && f['name'] == _rootName)
        .where((f) => (f['appProperties'] as Map?)?['notelore'] == 'root')
        .firstOrNull;
    if (root == null) return;
    final there = {for (final file in await _listAll(_app)) file['name']};
    for (final file in all) {
      final path = file == root ? null : _pathOf(file, root['id'], byId);
      if (path == null || file['md5Checksum'] == null || there.contains(path)) continue;
      await upload(path, await download(file['id']! as String), null);
    }
    await _json('PATCH', '$_files/${root['id']}', body: {'trashed': true});
    moved = true;
  }

  /// Every file the app can see in [space] that is not in the trash, page by
  /// page, in creation order.
  Future<List<Map<String, Object?>>> _listAll(String space) async {
    final all = <Map<String, Object?>>[];
    String? page;
    do {
      final answer = await _json(
        'GET',
        _files,
        query: {
          'q': 'trashed = false',
          if (space == _app) 'spaces': _app,
          'orderBy': 'createdTime',
          'pageSize': '1000',
          'fields': 'nextPageToken,files($_fields)',
          'pageToken': ?page,
        },
      );
      all.addAll((answer['files']! as List).cast<Map<String, Object?>>());
      page = answer['nextPageToken'] as String?;
    } while (page != null);
    return all;
  }

  /// The path of [file] under the folder [rootId], or null when it lies outside it.
  static String? _pathOf(
    Map<String, Object?> file,
    Object? rootId,
    Map<String, Map<String, Object?>> byId,
  ) {
    final names = <String>[];
    var current = file;
    for (var depth = 0; depth < 64; depth++) {
      names.add('${current['name']}');
      final parent = (current['parents'] as List?)?.first as String?;
      if (parent == rootId) return names.reversed.join('/');
      final next = byId[parent];
      if (next == null) return null;
      current = next;
    }
    return null; // a parent cycle or an absurd depth: not ours
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
        headers: {_contentType: 'text/markdown'},
        body: data,
      );
      return _remoteFile((jsonDecode(utf8.decode(response.bodyBytes)) as Map).cast());
    }
    final metadata = jsonEncode({
      'name': rel,
      'parents': [_app],
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
      headers: {_contentType: 'multipart/related; boundary=$boundary'},
      body: body,
    );
    return _remoteFile((jsonDecode(utf8.decode(response.bodyBytes)) as Map).cast());
  }

  /// Marks the file removed: Drive cannot trash a file in the app folder, so
  /// the mark keeps it [_kept] long, as the trash would.
  @override
  Future<void> trash(String fileId) async {
    await _json(
      'PATCH',
      '$_files/$fileId',
      body: {
        'appProperties': {'removed': _clock().toUtc().toIso8601String()},
      },
    );
  }

  Future<void> _delete(String fileId) => _send('DELETE', '$_files/$fileId');
}
