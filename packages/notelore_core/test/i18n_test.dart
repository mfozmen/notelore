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
    expect(sectionKey('Reminders'), 'reminders');
    expect(sectionKey('Hatırlatıcılar'), 'reminders');
    expect(sectionKey('Links'), isNull);
  });

  test('headings fall back to English', () {
    expect(sectionHeading('todo'), 'Todo');
    expect(sectionHeading('todo', 'tr'), 'Yapılacaklar');
    expect(sectionHeading('todo', 'de'), 'Todo');
  });

  test("a message's language: its small words, else Turkish letters (#653)", () {
    expect(messageLanguage('What did we decide about the database?'), 'en');
    expect(messageLanguage('Sprint review moved to Thursday.'), 'en');
    expect(messageLanguage('Ne karar verdik?'), 'tr');
    expect(messageLanguage('onaylıyorum'), 'tr');
    expect(messageLanguage('Kaydedildi: Ev Tadilatı.'), 'tr');
    expect(messageLanguage('ok'), isNull);
    expect(answerLanguage('Kaydedildi: Ev Tadilatı.'), isNull, reason: 'the eval stays strict');
  });
}
