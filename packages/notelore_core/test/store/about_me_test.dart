import 'dart:io';

import 'package:notelore_core/src/store/about_me.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  final now = DateTime.utc(2026, 11, 3, 9, 5, 7);

  setUp(() => root = Directory.systemTemp.createTempSync('about-me'));
  tearDown(() => root.deleteSync(recursive: true));

  String file() => File(aboutMePath(root.path)).readAsStringSync();
  List<String> history() => [
    for (final f in Directory(
      p.join(root.path, '.notelore', 'history'),
    ).listSync(recursive: true).whereType<File>())
      p.relative(f.path, from: root.path).replaceAll(r'\', '/'),
  ];

  test('no file is no facts', () => expect(aboutMe(root.path), isEmpty));

  test('the file sits at the notes root, outside every kind folder', () {
    expect(aboutMePath(root.path), p.join(root.path, 'about-me.md'));
  });

  test('a fact is a bullet in a plain Markdown file', () {
    rememberAboutMe(root.path, 'My wife is Ayşe.', now: now);
    rememberAboutMe(root.path, '  I live\n in Ankara. ', now: now);
    expect(file(), '# About me\n\n- My wife is Ayşe.\n- I live in Ankara.\n');
    expect(aboutMe(root.path), ['My wife is Ayşe.', 'I live in Ankara.']);
  });

  test('a fact already known, in any case, is not added twice', () {
    rememberAboutMe(root.path, 'I live in Ankara.', now: now);
    expect(() => rememberAboutMe(root.path, 'i live in ankara.', now: now), throwsArgumentError);
  });

  test('an empty fact is refused', () {
    expect(() => rememberAboutMe(root.path, '  ', now: now), throwsArgumentError);
  });

  test('a changed fact replaces its line; the old one stays only in history', () {
    rememberAboutMe(root.path, 'I live in Ankara.', now: now);
    rememberAboutMe(root.path, 'I work at Acme.', now: now);
    updateAboutMe(root.path, 'i live in ankara.', 'I live in İzmir.', now: now);
    expect(aboutMe(root.path), ['I live in İzmir.', 'I work at Acme.']);
    expect(history(), ['.notelore/history/2026-11-03T090507Z/about-me.md']);
    expect(
      File(p.join(root.path, history().single)).readAsStringSync(),
      contains('I live in Ankara.'),
    );
  });

  test('changing or forgetting a fact that is not there is refused', () {
    rememberAboutMe(root.path, 'I live in Ankara.', now: now);
    expect(() => updateAboutMe(root.path, 'I live in Paris.', 'x', now: now), throwsArgumentError);
    expect(() => forgetAboutMe(root.path, 'I live in Paris.', now: now), throwsArgumentError);
    expect(file(), '# About me\n\n- I live in Ankara.\n');
  });

  test('a change into a fact already known is refused', () {
    rememberAboutMe(root.path, 'A.', now: now);
    rememberAboutMe(root.path, 'B.', now: now);
    expect(() => updateAboutMe(root.path, 'A.', 'b.', now: now), throwsArgumentError);
  });

  test('a fact forgotten leaves the file; its copy goes to history', () {
    rememberAboutMe(root.path, 'I live in Ankara.', now: now);
    rememberAboutMe(root.path, 'I work at Acme.', now: now);
    forgetAboutMe(root.path, 'I work at Acme.', now: now);
    expect(aboutMe(root.path), ['I live in Ankara.']);
    expect(history(), hasLength(1));
  });

  test('two changes in the same second each keep their own copy', () {
    rememberAboutMe(root.path, 'A.', now: now);
    rememberAboutMe(root.path, 'B.', now: now);
    updateAboutMe(root.path, 'A.', 'C.', now: now);
    forgetAboutMe(root.path, 'B.', now: now);
    expect(history()..sort(), [
      '.notelore/history/2026-11-03T090507Z-2/about-me.md',
      '.notelore/history/2026-11-03T090507Z/about-me.md',
    ]);
    expect(
      File(p.join(root.path, '.notelore/history/2026-11-03T090507Z/about-me.md'))
          .readAsStringSync(),
      contains('- A.'),
    );
  });

  test('a file left with no fact gets its heading back with the next one', () {
    File(aboutMePath(root.path)).writeAsStringSync('- Only fact.\n');
    forgetAboutMe(root.path, 'Only fact.', now: now);
    rememberAboutMe(root.path, 'New fact.', now: now);
    expect(file(), '# About me\n\n- New fact.\n');
  });

  test('a file edited by hand: any bullet is a fact, other lines are kept', () {
    File(aboutMePath(root.path))
        .writeAsStringSync('# About me\r\n\r\nWritten by me.\r\n* Born 1985.\r\n- Two kids.\r\n');
    expect(aboutMe(root.path), ['Born 1985.', 'Two kids.']);
    forgetAboutMe(root.path, 'Born 1985.', now: now);
    expect(file(), '# About me\n\nWritten by me.\n- Two kids.\n');
  });

  test('NFD text from macOS matches its NFC form', () {
    rememberAboutMe(root.path, 'Şehir: İzmir', now: now);
    expect(() => rememberAboutMe(root.path, 'Şehir: İzmir', now: now), throwsArgumentError);
  });
}
