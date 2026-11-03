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

const _englishWords = {
  'the', 'a', 'an', 'and', 'to', 'of', 'in', 'on', 'for', 'with', 'is', 'are', 'was', 'it', //
  'i', "i've", "i'll", 'you', 'your', 'this', 'that', 'what', 'which', 'do', 'did', 'have',
};

const _turkishWords = {
  've', 'bir', 'bu', 'şu', 'için', 'ile', 'da', 'de', 'mi', 'mı', 'mu', 'mü', 'ne', 'olarak', //
  'ekledim', 'kaydettim', 'notuna', 'notunu', 'hangi', 'nasıl', 'var', 'yok', 'yani', 'değil',
};

/// `en` or `tr` by which language's small words [answer] has more of, quoted
/// text left out (a Turkish title in an English answer); null when neither.
String? answerLanguage(String answer) {
  final unquoted = answer.replaceAll(RegExp(r'"[^"]*"|“[^”]*”|`[^`]*`'), ' ');
  final words = RegExp(
    r"[\p{L}']+",
    unicode: true,
  ).allMatches(unquoted.toLowerCase()).map((m) => m[0]!);
  final english = words.where(_englishWords.contains).length;
  final turkish = words.where(_turkishWords.contains).length;
  if (english > turkish) return 'en';
  if (turkish > english) return 'tr';
  return null;
}

/// [message]'s language, for the line that ends the prompt (#653): by its
/// small words, as [answerLanguage] judges, else `tr` when it has letters only
/// Turkish uses ("onaylıyorum"); null when it says nothing ("ok").
String? messageLanguage(String message) =>
    answerLanguage(message) ?? (RegExp('[çğışöüÇĞİŞÖÜ]').hasMatch(message) ? 'tr' : null);
