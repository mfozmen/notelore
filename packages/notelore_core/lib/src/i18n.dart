/// Structural strings in English and Turkish; English is the fallback.
///
/// Note content is written in whatever language the user speaks; only the
/// structure (section headings, prompts) is translated here.
library;

const sectionHeadings = <String, Map<String, String>>{
  'decisions': {'en': 'Decisions', 'tr': 'Kararlar'},
  'notes': {'en': 'Notes', 'tr': 'Notlar'},
  'todo': {'en': 'Todo', 'tr': 'Yapılacaklar'},
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
