/// Reminders as events in the user's Google Calendar (#432), over the
/// Calendar v3 REST API.
///
/// The scope is `calendar.app.created`: Notelore makes a calendar of its own,
/// "Notelore", and can see and change only that one, never the user's other
/// calendars. Each event carries its reminder's id, so processing the notes
/// again changes nothing; a deleted event goes to Google Calendar's trash.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../providers/http.dart';
import '../reminders.dart';
import 'drive.dart' show AccessToken;

const calendarScope = 'https://www.googleapis.com/auth/calendar.app.created';

const _api = 'https://www.googleapis.com/calendar/v3';
const _name = 'Notelore';

/// The event's private mark: the reminder it stands for.
const _mark = 'notelore';

/// What the reminders need of a calendar; [GoogleCalendar], or a fake in tests.
abstract interface class ReminderCalendar {
  /// The id of Notelore's calendar: [known] while it is still there, else a new one.
  Future<String> calendarId(String? known);

  /// Makes the calendar's events after [now] exactly [due]; past ones stay.
  Future<void> sync(String calendarId, List<DueReminder> due, {required DateTime now});

  /// Removes the events after [now], when reminders come back to the device.
  Future<void> clear(String calendarId, {required DateTime now});
}

class GoogleCalendar implements ReminderCalendar {
  GoogleCalendar(this._client, this._token, {this.timeout = const Duration(seconds: 30)});

  /// How long one request may take before it counts as offline.
  final Duration timeout;

  final http.Client _client;
  final AccessToken _token;

  @override
  Future<String> calendarId(String? known) async {
    if (known != null) {
      try {
        await _call('GET', '/calendars/${Uri.encodeComponent(known)}');
        return known;
      } on HttpError catch (error) {
        if (error.status != 404) rethrow; // deleted in Google Calendar: make it again
      }
    }
    final made = await _call('POST', '/calendars', body: {'summary': _name});
    return made['id']! as String;
  }

  @override
  Future<void> sync(String calendarId, List<DueReminder> due, {required DateTime now}) async {
    final events = await _coming(calendarId, now);
    final wanted = {for (final reminder in due) '${reminder.id}': reminder};
    for (final MapEntry(key: mark, value: event) in events.entries) {
      if (!wanted.containsKey(mark)) await _delete(calendarId, event);
    }
    for (final MapEntry(key: mark, value: reminder) in wanted.entries) {
      if (!events.containsKey(mark)) {
        await _call(
          'POST',
          '/calendars/${Uri.encodeComponent(calendarId)}/events',
          body: _event(reminder),
        );
      }
    }
  }

  @override
  Future<void> clear(String calendarId, {required DateTime now}) async {
    for (final event in (await _coming(calendarId, now)).values) {
      await _delete(calendarId, event);
    }
  }

  /// The calendar's events after [now], by their reminder's id.
  Future<Map<String, String>> _coming(String calendarId, DateTime now) async {
    final found = <String, String>{};
    String? page;
    do {
      final listed = await _call(
        'GET',
        '/calendars/${Uri.encodeComponent(calendarId)}/events',
        query: {
          'timeMin': now.toUtc().toIso8601String(),
          'singleEvents': 'true',
          'maxResults': '250',
          'pageToken': ?page,
        },
      );
      for (final event
          in (listed['items'] as List?)?.cast<Map<String, Object?>>() ??
              const <Map<String, Object?>>[]) {
        final mark = ((event['extendedProperties'] as Map?)?['private'] as Map?)?[_mark];
        if (mark is String) found[mark] = event['id']! as String;
      }
      page = listed['nextPageToken'] as String?;
    } while (page != null);
    return found;
  }

  Future<void> _delete(String calendarId, String eventId) async {
    try {
      await _call(
        'DELETE',
        '/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(eventId)}',
      );
    } on HttpError catch (error) {
      if (error.status != 410) rethrow; // already gone
    }
  }

  /// A short event at the reminder's minute; Google notifies at its start.
  static Map<String, Object?> _event(DueReminder reminder) {
    String at(DateTime time) => time.toUtc().toIso8601String();
    return {
      'summary': reminder.text,
      'description': '${reminder.note} · $_name',
      'start': {'dateTime': at(reminder.at)},
      'end': {'dateTime': at(reminder.at.add(const Duration(minutes: 15)))},
      'reminders': {
        'useDefault': false,
        'overrides': [
          {'method': 'popup', 'minutes': 0},
        ],
      },
      'extendedProperties': {
        'private': {_mark: '${reminder.id}'},
      },
    };
  }

  Future<Map<String, Object?>> _call(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    for (var refresh = false; ; refresh = true) {
      final request = http.Request(method, Uri.parse('$_api$path').replace(queryParameters: query))
        ..headers['Authorization'] = 'Bearer ${await _token(refresh: refresh)}';
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json; charset=UTF-8'
          ..body = jsonEncode(body);
      }
      final http.Response response;
      try {
        response = await _client.send(request).then(http.Response.fromStream).timeout(timeout);
      } on http.ClientException catch (error) {
        throw NetworkError(error.message);
      } on TimeoutException {
        throw const NetworkError('Google Calendar did not answer in time');
      }
      if (response.statusCode == 401 && !refresh) continue; // expired: refresh once
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode >= 400) throw HttpError(response.statusCode, errorMessage(text));
      return text.isEmpty ? const {} : jsonDecode(text) as Map<String, Object?>;
    }
  }
}
