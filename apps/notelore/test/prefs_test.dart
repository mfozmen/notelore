import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/prefs.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';

void main() {
  const prefs = SharedPrefs(
    language: AppLanguage.tr,
    appearance: Appearance.dark,
    webSearch: false,
    aboutMeToCloud: true,
    calendar: true,
    calendarId: 'cal1',
  );

  test('the shared file keeps the keys older versions read (#662)', () {
    expect(
      jsonEncode(prefs.toJson()),
      jsonEncode({
        'language': 'tr',
        'appearance': 'dark',
        'webSearch': false,
        'aboutMeToCloud': true,
        'calendar': true,
        'calendarId': 'cal1',
      }),
    );
    expect(const SharedPrefs(calendar: false).toJson(), {'calendar': false});
  });

  test('read back, it is the same; what a file does not say is null', () {
    final back = SharedPrefs.fromJson(prefs.toJson());
    expect(back.toJson(), prefs.toJson());
    final empty = SharedPrefs.fromJson({
      'language': 'klingon',
      'webSearch': 'yes',
      'calendarId': 7,
    });
    expect([
      empty.language,
      empty.webSearch,
      empty.calendar,
      empty.calendarId,
    ], everyElement(isNull));
    expect(empty.toJson(), isEmpty);
  });

  test('a file from a version with palettes still loads; the palette is dropped (#782)', () {
    final old = SharedPrefs.fromJson({'palette': 'forest', 'appearance': 'dark'});
    expect(old.appearance, Appearance.dark);
    expect(old.toJson(), {'appearance': 'dark'});
  });
}
