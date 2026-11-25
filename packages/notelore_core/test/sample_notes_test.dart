import 'package:notelore_core/src/sample_notes.dart';
import 'package:notelore_core/src/store/format.dart';
import 'package:notelore_core/src/store/notes.dart' show slugify;
import 'package:test/test.dart';

void main() {
  final newest = DateTime(2026, 10, 17);

  test('makes count invented notes, the same every time', () {
    final notes = sampleNotes(300, newest: newest, days: 400);
    expect(notes, hasLength(300));
    expect(sampleNotes(300, newest: newest, days: 400), notes);
  });

  test('every note parses, its path is its slug, and both kinds and languages occur', () {
    final notes = sampleNotes(300, newest: newest, days: 400);
    final kinds = <String>{};
    final headings = <String>{};
    for (final MapEntry(key: path, value: text) in notes.entries) {
      final note = parse(text);
      final kind = '${note.meta['kind']}';
      kinds.add(kind);
      headings.addAll(note.sections.map((s) => s.heading));
      expect(path, '${kind}s/${slugify(note.title)}.md');
      expect(serialize(note), text, reason: 'round-trips like a real note');
    }
    expect(kinds, {'project', 'topic'});
    expect(headings, containsAll(['Decisions', 'Notes', 'Todo', 'Kararlar', 'Notlar']));
  });

  test('note i was last updated i * days / count days before newest, never later', () {
    final notes = sampleNotes(10, newest: newest, days: 5).values.map(parse).toList();
    DateTime day(Note note, String key) => note.meta[key]! as DateTime;
    expect(day(notes.first, 'updated'), DateTime.utc(2026, 10, 17));
    expect(day(notes.last, 'updated'), DateTime.utc(2026, 10, 13));
    for (final note in notes) {
      expect(day(note, 'created').isAfter(day(note, 'updated')), isFalse);
    }
  });

  test('sizes vary like real notes: a few lines up to a few kilobytes', () {
    final sizes = sampleNotes(200, newest: newest, days: 200).values.map((t) => t.length);
    expect(sizes.reduce((a, b) => a < b ? a : b), lessThan(600));
    expect(sizes.reduce((a, b) => a > b ? a : b), greaterThan(2000));
  });
}
