/// Invented notes in the note format, for the load test and the eval cases that
/// need a notes folder with many notes (#895). Never real notes: every word
/// comes from the lists below.
library;

import 'dart:math';

import 'store/format.dart' show isoDate;
import 'store/notes.dart' show slugify;

typedef _Language = ({
  List<String> subjects,
  List<String> qualifiers,
  List<String> entries,
  List<String> todos,
  List<(String, String)> decisions,
  List<String> tags,
  String decisionsHeading,
  String notesHeading,
  String todoHeading,
});

const _english = (
  subjects: [
    'Garden Irrigation',
    'Bike Maintenance',
    'Kitchen Herbs',
    'Running Plan',
    'Photo Archive',
    'Home Network',
    'Balcony Plants',
    'Camping Gear',
    'Language Course',
    'Piano Practice',
    'Wedding Gifts',
    'Car Service',
    'Podcast Ideas',
    'Team Offsite',
    'Newsletter',
    'Board Games',
    'Coffee Brewing',
    'Climbing Trips',
    'Laptop Setup',
    'Grant Application',
    'Moving House',
    'Dentist Visits',
    'Bird Feeder',
    'Sourdough',
    'Conference Talk',
    'Insurance Claims',
    'Volunteer Shifts',
    'Office Chairs',
    'Aquarium',
    'Music Festival',
  ],
  qualifiers: ['', 'Spring', 'Weekend', 'Family', 'Office', 'Summer', 'Winter', 'Shared'],
  entries: [
    'Called the shop about the {thing}; they can do it next {day}.',
    'Compared three options for the {thing} and the second one is cheapest.',
    'The {thing} took longer than planned, about {n} hours in total.',
    'Asked Ana for advice on the {thing}; she suggested waiting until {day}.',
    'Wrote down the measurements for the {thing}: {n} by {n} centimetres.',
    'Found a cheaper supplier for the {thing}, roughly {n} euros less.',
  ],
  todos: [
    'Order a new {thing}',
    'Book a slot for the {thing} on {day}',
    'Send the {thing} photos to Ana',
    'Check the warranty of the {thing}',
  ],
  decisions: [
    ('vendor', 'The local shop. Faster delivery.'),
    ('schedule', 'Every second {day}. Fits the routine.'),
    ('color', 'Dark green. Hides dirt.'),
    ('location', 'The back room. More light.'),
  ],
  tags: ['home', 'family', 'work', 'outdoor', 'hobby', 'health', 'travel', 'money'],
  decisionsHeading: 'Decisions',
  notesHeading: 'Notes',
  todoHeading: 'Todo',
);

const _turkish = (
  subjects: [
    'Bahçe Sulama',
    'Bisiklet Bakımı',
    'Balkon Bitkileri',
    'Koşu Planı',
    'Fotoğraf Arşivi',
    'Ev Ağı',
    'Kamp Malzemeleri',
    'Almanca Kursu',
    'Gitar Çalışması',
    'Düğün Hediyeleri',
    'Araba Servisi',
    'Podcast Fikirleri',
    'Ekip Toplantısı',
    'Bülten',
    'Kutu Oyunları',
    'Kahve Demleme',
    'Tırmanış Gezileri',
    'Dizüstü Kurulumu',
    'Hibe Başvurusu',
    'Taşınma',
    'Diş Hekimi',
    'Kuş Yemliği',
    'Ekşi Maya',
    'Konferans Sunumu',
    'Sigorta İşleri',
    'Gönüllü Nöbetler',
    'Ofis Sandalyeleri',
    'Akvaryum',
    'Müzik Festivali',
    'Yoga Dersleri',
  ],
  qualifiers: ['', 'Bahar', 'Hafta Sonu', 'Aile', 'Ofis', 'Yaz', 'Kış', 'Ortak'],
  entries: [
    '{thing} için dükkânı aradım; {day} günü yapabiliyorlar.',
    '{thing} için üç seçeneği karşılaştırdım, ikincisi en ucuzu.',
    '{thing} planlanandan uzun sürdü, toplam {n} saat kadar.',
    '{thing} konusunda Zeynep\'e danıştım; {day} gününe kadar beklemeyi önerdi.',
    '{thing} ölçülerini not ettim: {n} x {n} santimetre.',
    '{thing} için daha ucuz bir satıcı buldum, yaklaşık {n} lira daha az.',
  ],
  todos: [
    'Yeni {thing} sipariş et',
    '{thing} için {day} gününe randevu al',
    '{thing} fotoğraflarını Zeynep\'e gönder',
    '{thing} garantisini kontrol et',
  ],
  decisions: [
    ('satıcı', 'Mahalledeki dükkân. Teslimat daha hızlı.'),
    ('takvim', 'İki haftada bir {day}. Rutine uyuyor.'),
    ('renk', 'Koyu yeşil. Kiri göstermiyor.'),
    ('yer', 'Arka oda. Daha aydınlık.'),
  ],
  tags: ['ev', 'aile', 'iş', 'doğa', 'hobi', 'sağlık', 'seyahat', 'para'],
  decisionsHeading: 'Kararlar',
  notesHeading: 'Notlar',
  todoHeading: 'Yapılacaklar',
);

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];

/// Entries per note, a few to many as real notes have.
const _sizes = [1, 2, 3, 5, 8, 13, 21, 34];

/// [count] invented notes, relative path (`/`) to text, newest first: note i
/// was last updated `i * days ~/ count` days before [newest]. The same for the
/// same arguments; even-numbered notes are English, odd ones Turkish.
Map<String, String> sampleNotes(int count, {required DateTime newest, required int days}) {
  final random = Random(895);
  final notes = <String, String>{};
  final english = <String>[];
  final turkish = <String>[];
  for (var i = 0; i < count; i++) {
    final turkce = i.isOdd;
    final language = turkce ? _turkish : _english;
    final titles = turkce ? turkish : english;
    final title = _title(language, titles.length);
    titles.add(title);
    final updated = DateTime.utc(newest.year, newest.month, newest.day - i * days ~/ count);
    final kind = random.nextInt(5) < 2 ? 'project' : 'topic';
    notes['${kind}s/${slugify(title)}.md'] = _note(
      random,
      language,
      turkce ? _gunler : _days,
      title,
      kind,
      updated,
    );
  }
  return notes;
}

/// The [n]th title of [language]: every subject once, then with each
/// qualifier, then numbered, so no two notes share a slug.
String _title(_Language language, int n) {
  final subjects = language.subjects.length;
  final qualifiers = language.qualifiers.length;
  final subject = language.subjects[n % subjects];
  final qualifier = language.qualifiers[n ~/ subjects % qualifiers];
  final round = n ~/ (subjects * qualifiers);
  return [if (qualifier.isNotEmpty) qualifier, subject, if (round > 0) '${round + 1}'].join(' ');
}

String _note(
  Random random,
  _Language language,
  List<String> days,
  String title,
  String kind,
  DateTime updated,
) {
  final size = _sizes[random.nextInt(_sizes.length)];
  final created = DateTime.utc(updated.year, updated.month, updated.day - size * 3);
  final thing = title.toLowerCase();
  String fill(String template) => template
      .replaceAll('{thing}', thing)
      .replaceAll('{day}', days[random.nextInt(days.length)])
      .replaceAllMapped('{n}', (_) => '${2 + random.nextInt(60)}');
  String date(int step) => isoDate(DateTime.utc(created.year, created.month, created.day + step));

  final tags = {
    for (var t = 0; t <= random.nextInt(3); t++)
      language.tags[random.nextInt(language.tags.length)],
  };
  final decisions = [
    for (var d = 0; d < size ~/ 8; d++)
      if (language.decisions[(d + size) % language.decisions.length] case (
        final topic,
        final value,
      ))
        '- ${date(d)} — **$topic**: ${fill(value)}',
  ];
  final entries = [
    for (var e = 0; e < size; e++) '- ${date(e * 3 + 3)}: ${fill(_pick(random, language.entries))}',
  ];
  final todos = [
    for (var t = 0; t < size ~/ 4; t++)
      '- [${t.isEven ? ' ' : 'x'}] ${date(t * 3 + 1)}: ${fill(_pick(random, language.todos))}',
  ];
  return [
    '---',
    'title: $title',
    'kind: $kind',
    'created: ${isoDate(created)}',
    'updated: ${isoDate(updated)}',
    'tags: [${tags.join(', ')}]',
    '---',
    '# $title',
    if (decisions.isNotEmpty) ...['', '## ${language.decisionsHeading}', ...decisions],
    ...['', '## ${language.notesHeading}', ...entries],
    if (todos.isNotEmpty) ...['', '## ${language.todoHeading}', ...todos],
    '',
  ].join('\n');
}

String _pick(Random random, List<String> from) => from[random.nextInt(from.length)];
