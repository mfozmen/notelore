import 'package:notelore_core/src/i18n.dart';
import 'package:test/test.dart';

void main() {
  test('every known heading variant maps to its key', () {
    expect(sectionKey('Decisions'), 'decisions');
    expect(sectionKey('Kararlar'), 'decisions');
    expect(sectionKey('Notes'), 'notes');
    expect(sectionKey('Notlar'), 'notes');
    expect(sectionKey('Todo'), 'todo');
    expect(sectionKey('Yapılacaklar'), 'todo');
    expect(sectionKey('Links'), isNull);
  });

  test('headings fall back to English', () {
    expect(sectionHeading('todo'), 'Todo');
    expect(sectionHeading('todo', 'tr'), 'Yapılacaklar');
    expect(sectionHeading('todo', 'de'), 'Todo');
  });
}
