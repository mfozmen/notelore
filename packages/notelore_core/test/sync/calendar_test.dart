import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:notelore_core/src/reminders.dart';
import 'package:notelore_core/src/sync/calendar.dart';
import 'package:test/test.dart';

/// Google Calendar's v3 REST API, the parts Notelore uses, in memory.
class FakeCalendarApi {
  final calendars = <String, String>{}; // id -> summary
  final events = <String, Map<String, Map<String, Object?>>>{}; // calendar -> id -> event
  final requests = <String>[];
  var token = 't1';
  var _next = 0;

  /// Events per page, to make the client follow nextPageToken.
  var pageSize = 2;

  /// What a delete answers instead, when set.
  int? deleteStatus;

  /// Calendars that exist but are not this app's to see.
  final forbidden = <String>{};

  /// What creating a calendar answers instead, when set.
  String? madeAnswer;

  late final http.Client client = MockClient((request) async {
    requests.add('${request.method} ${request.url.path}');
    if (request.headers['Authorization'] != 'Bearer $token') {
      return http.Response('{"error": {"message": "Invalid Credentials"}}', 401);
    }
    final path = request.url.pathSegments.skip(2).toList(); // after calendar/v3
    final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, Object?>;
    switch ((request.method, path)) {
      case ('POST', ['calendars']) when madeAnswer != null:
        return http.Response(madeAnswer!, 200);
      case ('POST', ['calendars']):
        final id = 'cal${_next++}@group.calendar.google.com';
        calendars[id] = body!['summary']! as String;
        events[id] = {};
        return _json({'id': id, 'summary': calendars[id]});
      case ('GET', ['calendars', final id]) when forbidden.contains(id):
        return http.Response('{"error": {"message": "Forbidden"}}', 403);
      case ('GET', ['calendars', final id]):
        return calendars.containsKey(id) ? _json({'id': id, 'summary': calendars[id]}) : _missing();
      case ('GET', ['calendars', final id, 'events']):
        final all = events[id];
        if (all == null) return _missing();
        // Like Google: an event is listed while its end is after timeMin.
        final min = DateTime.parse(request.url.queryParameters['timeMin']!);
        final coming = [
          for (final e in all.values)
            if (DateTime.parse((e['end']! as Map)['dateTime']! as String).isAfter(min)) e,
        ];
        final from = int.parse(request.url.queryParameters['pageToken'] ?? '0');
        final page = coming.skip(from).take(pageSize).toList();
        final more = from + pageSize < coming.length;
        return _json({'items': page, if (more) 'nextPageToken': '${from + pageSize}'});
      case ('POST', ['calendars', final id, 'events']):
        final eventId = 'ev${_next++}';
        events[id]![eventId] = {...body!, 'id': eventId};
        return _json(events[id]![eventId]!);
      case ('DELETE', ['calendars', final id, 'events', final eventId]):
        if (deleteStatus case final status?) return http.Response('{}', status);
        return events[id]!.remove(eventId) == null
            ? http.Response('', 410)
            : http.Response('', 204);
    }
    return http.Response('no route', 500);
  });

  static http.Response _json(Object value) =>
      http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'});
  static http.Response _missing() => http.Response('{"error": {"message": "Not Found"}}', 404);
}

DueReminder due(int id, DateTime at, [String text = 'Dentist']) =>
    DueReminder(id, at, 'Health', '$text $id');

void main() {
  late FakeCalendarApi api;
  late List<bool> refreshes;
  late String held; // the token the client has
  setUp(() {
    api = FakeCalendarApi();
    refreshes = [];
    held = api.token;
  });

  GoogleCalendar calendar() => GoogleCalendar(api.client, ({bool refresh = false}) async {
    refreshes.add(refresh);
    if (refresh) held = api.token;
    return held;
  });

  final now = DateTime(2026, 10, 19, 14);

  test("Notelore's own calendar is made once, and found again (#432)", () async {
    final id = await calendar().calendarId(null);
    expect(api.calendars, {id: 'Notelore'});
    expect(await calendar().calendarId(id), id);
    expect(api.calendars, hasLength(1));
    // Deleted by the user in Google Calendar: a new one.
    api.calendars.remove(id);
    final again = await calendar().calendarId(id);
    expect(again, isNot(id));
  });

  test("an id from elsewhere is used only while it is Notelore's own calendar", () async {
    // Not this app's to see (another account's, or planted in the shared settings).
    api.forbidden.add('someone-else');
    expect(await calendar().calendarId('someone-else'), isNot('someone-else'));
    // A calendar by another name is not Notelore's either.
    api.calendars['other'] = 'Work';
    expect(await calendar().calendarId('other'), isNot('other'));
    expect(api.calendars.values.where((name) => name == 'Notelore'), hasLength(2));
  });

  test('an answer without what it must have is a format error, not a crash', () async {
    api.madeAnswer = '{}';
    expect(() => calendar().calendarId(null), throwsA(isA<FormatException>()));
  });

  test('an event uses its end, or a realistic one for its kind (#535)', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    final match = DueReminder(1, DateTime(2026, 10, 20, 20), 'Sport', 'Football match');
    final dinner = DueReminder(
      2,
      DateTime(2026, 10, 21, 19),
      'Food',
      'Dinner',
      end: DateTime(2026, 10, 21, 21, 30),
    );
    await cal.sync(id, [match, dinner], now: now);
    final events = api.events[id]!.values.toList();
    String ends(Map<String, Object?> event) => (event['end']! as Map)['dateTime']! as String;
    expect(
      ends(events.firstWhere((e) => e['summary'] == 'Football match')),
      DateTime(2026, 10, 20, 22).toUtc().toIso8601String(),
    );
    expect(
      ends(events.firstWhere((e) => e['summary'] == 'Dinner')),
      DateTime(2026, 10, 21, 21, 30).toUtc().toIso8601String(),
    );
  });

  test('an end change replaces the event, never leaves the old one (#535)', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    final at = DateTime(2026, 10, 21, 20);
    await cal.sync(id, [
      DueReminder(1, at, 'Sport', 'Match', end: at.add(const Duration(hours: 2))),
    ], now: now);
    final first = api.events[id]!.values.single;
    expect(
      (first['end']! as Map)['dateTime'],
      at.add(const Duration(hours: 2)).toUtc().toIso8601String(),
    );
    await cal.sync(id, [
      DueReminder(2, at, 'Sport', 'Match', end: at.add(const Duration(hours: 3))),
    ], now: now);
    final events = api.events[id]!.values.toList();
    expect(events, hasLength(1));
    expect(
      (events.single['end']! as Map)['dateTime'],
      at.add(const Duration(hours: 3)).toUtc().toIso8601String(),
    );
  });

  test('the coming events are exactly the coming reminders, each once', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    final first = [for (var i = 1; i <= 3; i++) due(i, DateTime(2026, 10, 20 + i, 9, 30))];
    await cal.sync(id, first, now: now);
    final events = api.events[id]!.values.toList();
    expect(events, hasLength(3));
    final event = events.firstWhere((e) => e['summary'] == 'Dentist 1');
    expect(event['description'], 'Health · Notelore');
    expect(
      (event['start']! as Map)['dateTime'],
      DateTime(2026, 10, 21, 9, 30).toUtc().toIso8601String(),
    );
    expect(
      (event['end']! as Map)['dateTime'],
      DateTime(2026, 10, 21, 9, 45).toUtc().toIso8601String(),
    );
    // Google itself notifies, on every device, at the event's start.
    expect(event['reminders'], {
      'useDefault': false,
      'overrides': [
        {'method': 'popup', 'minutes': 0},
      ],
    });
    // Processing the same notes again changes nothing (over pages too).
    final created = api.requests.where((r) => r.startsWith('POST')).length;
    await cal.sync(id, first, now: now);
    expect(api.requests.where((r) => r.startsWith('POST')), hasLength(created));
    // The same reminder in other words (the app lock hides them): replaced.
    await cal.sync(id, [
      DueReminder(1, DateTime(2026, 10, 21, 9, 30), 'Notelore', 'Hidden'),
    ], now: now);
    expect(api.events[id]!.values.map((e) => e['summary']), ['Hidden']);
    await cal.sync(id, first, now: now);
    // One gone from the notes, one new: deleted and added.
    await cal.sync(id, [first[0], first[2], due(4, DateTime(2026, 11, 1, 8))], now: now);
    expect(
      api.events[id]!.values.map((e) => e['summary']),
      unorderedEquals(['Dentist 1', 'Dentist 3', 'Dentist 4']),
    );
  });

  test('two devices writing at once: the twin event is removed', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    final one = [due(1, DateTime(2026, 10, 21, 9))];
    await cal.sync(id, one, now: now);
    final twin = api.events[id]!.values.single;
    api.events[id]!['ev-twin'] = {...twin, 'id': 'ev-twin'};
    await cal.sync(id, one, now: now);
    expect(api.events[id], hasLength(1));
  });

  test('a reminder that has just come keeps its event', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    final at = now.subtract(const Duration(minutes: 5)); // still listed: it ends in 10
    await cal.sync(id, [due(1, at)], now: at.subtract(const Duration(hours: 1)));
    await cal.sync(id, const [], now: now);
    expect(api.events[id], hasLength(1));
  });

  test('past events stay, and clearing removes only the coming ones', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    await cal.sync(id, [
      due(1, DateTime(2026, 10, 19, 10)),
      due(2, DateTime(2026, 10, 25, 10)),
    ], now: DateTime(2026, 10, 18));
    // Later: the first has passed, and the notes no longer list it as coming.
    await cal.sync(id, [due(2, DateTime(2026, 10, 25, 10))], now: now);
    expect(api.events[id], hasLength(2));
    await cal.clear(id, now: now);
    expect(api.events[id]!.values.map((e) => e['summary']), ['Dentist 1']);
  });

  test('an event the user already deleted is fine; another error is not', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    await cal.sync(id, [due(1, DateTime(2026, 10, 21, 9))], now: now);
    api.deleteStatus = 410; // Gone
    await cal.clear(id, now: now);
    api.deleteStatus = 500;
    expect(() => cal.clear(id, now: now), throwsA(isA<HttpError>()));
  });

  test('an expired token is refreshed once; an error says what Google said', () async {
    final cal = calendar();
    final id = await cal.calendarId(null);
    api.token = 't2'; // the held one expired
    await cal.sync(id, [due(1, DateTime(2026, 10, 21, 9))], now: now);
    expect(refreshes, contains(true));
    expect(
      () => calendar().sync('gone', [], now: now),
      throwsA(isA<HttpError>().having((e) => e.status, 'status', 404)),
    );
  });

  test('offline and too slow are network errors', () async {
    final offline = GoogleCalendar(
      MockClient((_) => throw http.ClientException('no route to host')),
      ({bool refresh = false}) async => 't',
    );
    expect(() => offline.calendarId(null), throwsA(isA<NetworkError>()));
    final slow = GoogleCalendar(
      MockClient((_) => Completer<http.Response>().future),
      ({bool refresh = false}) async => 't',
      timeout: const Duration(milliseconds: 10),
    );
    expect(() => slow.calendarId(null), throwsA(isA<NetworkError>()));
  });
}
