import 'package:notelore_core/src/text.dart';
import 'package:test/test.dart';

void main() {
  test('splitLines cuts at every Python line boundary', () {
    const text = 'a\r\nb\rc\nd\ve\ff\x1cg\x1dh\x1ei\x85j\u2028k\u2029l';
    expect(splitLines(text), 'abcdefghijkl'.split(''));
    expect(splitLines(text, keepEnds: true).join(), text);
    expect(splitLines(text, keepEnds: true).first, 'a\r\n');
  });

  test('no empty last line, and nothing for empty text', () {
    expect(splitLines('a\n'), ['a']);
    expect(splitLines('a\n\n', keepEnds: true), ['a\n', '\n']);
    expect(splitLines(''), isEmpty);
  });
}
