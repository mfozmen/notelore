/// The settings every device shares through Drive (#662), in one place: how
/// they are written to the shared file and this device's own, and read back.
library;

import 'strings.dart';
import 'theme.dart';

/// A field is null when a file does not say it, so a reader keeps its own value
/// or its default; older app versions read the same keys.
final class SharedPrefs {
  const SharedPrefs({
    this.language,
    this.palette,
    this.appearance,
    this.webSearch,
    this.aboutMeToCloud,
    this.calendar,
    this.calendarId,
  });

  factory SharedPrefs.fromJson(Map<Object?, Object?> json) => SharedPrefs(
    language: _named(AppLanguage.values, json['language']),
    palette: _named(Palette.values, json['palette']),
    appearance: _named(Appearance.values, json['appearance']),
    webSearch: json['webSearch'] is bool ? json['webSearch']! as bool : null,
    aboutMeToCloud: json['aboutMeToCloud'] is bool ? json['aboutMeToCloud']! as bool : null,
    calendar: json['calendar'] is bool ? json['calendar']! as bool : null,
    calendarId: json['calendarId'] is String ? json['calendarId']! as String : null,
  );

  final AppLanguage? language;
  final Palette? palette;
  final Appearance? appearance;
  final bool? webSearch;
  final bool? aboutMeToCloud;
  final bool? calendar;
  final String? calendarId;

  Map<String, Object?> toJson() => {
    'language': ?language?.name,
    'palette': ?palette?.name,
    'appearance': ?appearance?.name,
    'webSearch': ?webSearch,
    'aboutMeToCloud': ?aboutMeToCloud,
    'calendar': ?calendar,
    'calendarId': ?calendarId,
  };
}

T? _named<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;
