/// Structural strings in English and Turkish; English is the fallback.
///
/// Note content is written in whatever language the user speaks; only the
/// structure (section headings, prompts) is translated here.
library;

const sectionHeadings = <String, Map<String, String>>{
  'decisions': {'en': 'Decisions', 'tr': 'Kararlar'},
  'notes': {'en': 'Notes', 'tr': 'Notlar'},
  'todo': {'en': 'Todo', 'tr': 'Yapılacaklar'},
  'reminders': {'en': 'Reminders', 'tr': 'Hatırlatıcılar'},
};

/// The about-me file's sections, in the order they are written and shown (#671).
/// Facts outside a known heading are Other.
const aboutMeSections = <String, Map<String, String>>{
  'work': {'en': 'Work', 'tr': 'İş'},
  'home': {'en': 'Home', 'tr': 'Ev'},
  'family': {'en': 'Family', 'tr': 'Aile'},
  'health': {'en': 'Health', 'tr': 'Sağlık'},
  'other': {'en': 'Other', 'tr': 'Diğer'},
};

final _headingToKey = {
  for (final MapEntry(:key, :value) in sectionHeadings.entries)
    for (final heading in value.values) heading: key,
};

/// The canonical key for a known section heading in any language, else null.
String? sectionKey(String heading) => _headingToKey[heading];

String sectionHeading(String key, [String lang = 'en']) {
  final variants = sectionHeadings[key]!;
  return variants[lang] ?? variants['en']!;
}
