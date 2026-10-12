import 'dart:io';

import 'package:test/test.dart';

import 'coverage_gate.dart';

const _full = '''
SF:lib/a.dart
DA:1,1
DA:2,3
LF:2
LH:2
end_of_record
''';

const _partial = '''
SF:lib/b.dart
DA:4,1
DA:7,0
DA:9,0
LF:3
LH:1
end_of_record
''';

/// An lcov record from its lines.
String _lcov(List<String> lines) => [...lines, 'end_of_record', ''].join(String.fromCharCode(10));

void main() {
  test('fully covered files have nothing missing', () {
    expect(missingLines(_full), isEmpty);
  });

  test('every unhit line is reported with its file', () {
    expect(missingLines(_full + _partial), {
      'lib/b.dart': [7, 9],
    });
  });

  test('the gate passes at 100% and fails below, naming the gaps', () async {
    final dir = await Directory.systemTemp.createTemp('gate');
    addTearDown(() => dir.delete(recursive: true));
    final good = File('${dir.path}/good.info')..writeAsStringSync(_full);
    final bad = File('${dir.path}/bad.info')..writeAsStringSync(_partial);
    final out = StringBuffer();
    expect(gate([good.path], out), 0);
    expect(out.toString(), contains('100% line coverage'));
    out.clear();
    expect(gate([good.path, bad.path], out), 1);
    expect(out.toString(), contains('lib/b.dart: 7, 9'));
  });

  test('the same relative path in two reports keeps both sets of gaps', () async {
    final dir = await Directory.systemTemp.createTemp('gate');
    addTearDown(() => dir.delete(recursive: true));
    const second = 'SF:lib/b.dart\nDA:11,0\nend_of_record\n';
    final one = File('${dir.path}/one.info')..writeAsStringSync(_partial);
    final two = File('${dir.path}/two.info')..writeAsStringSync(second);
    final out = StringBuffer();
    expect(gate([one.path, two.path], out), 1);
    expect(out.toString(), allOf(contains('lib/b.dart: 7, 9'), contains('lib/b.dart: 11')));
    expect(out.toString(), contains(one.path));
    expect(out.toString(), contains(two.path));
  });

  test('a missing report is an error, not a pass', () {
    final out = StringBuffer();
    expect(gate(['does/not/exist.info'], out), 1);
    expect(out.toString(), contains('no coverage report'));
  });

  test('lines marked coverage:ignore (native code tests cannot load) do not count', () {
    const source = '''
void a() {}
// coverage:ignore-start
void b() {
  native();
}
// coverage:ignore-end
void c() {} // coverage:ignore-line
void d() {}
''';
    expect(ignoredLines(source), {2, 3, 4, 5, 6, 7});
  });

  test('the gate reads each source next to its report and skips ignored lines', () async {
    final dir = await Directory.systemTemp.createTemp('gate');
    addTearDown(() => dir.delete(recursive: true));
    Directory('${dir.path}/lib').createSync();
    Directory('${dir.path}/coverage').createSync();
    File('${dir.path}/lib/n.dart').writeAsStringSync('''
void a() {}
// coverage:ignore-start
void b() => native();
// coverage:ignore-end
void c() {}
''');
    final report = File('${dir.path}/coverage/lcov.info')
      ..writeAsStringSync(_lcov(['SF:lib/n.dart', 'DA:1,1', 'DA:3,0', 'DA:5,0']));
    final out = StringBuffer();
    expect(gate([report.path], out), 1);
    expect(out.toString(), contains('lib/n.dart: 5')); // 3 is ignored, 5 is not
    expect(out.toString(), isNot(contains('3, 5')));
    // A source that cannot be read ignores nothing.
    final elsewhere = File('${dir.path}/other.info')
      ..writeAsStringSync(_lcov(['SF:lib/gone.dart', 'DA:2,0']));
    out.clear();
    expect(gate([elsewhere.path], out), 1);
    expect(out.toString(), contains('lib/gone.dart: 2'));
  });

  test('an ignore-start that is never closed fails the gate rather than hide the file', () async {
    final dir = await Directory.systemTemp.createTemp('gate');
    addTearDown(() => dir.delete(recursive: true));
    Directory('${dir.path}/lib').createSync();
    Directory('${dir.path}/coverage').createSync();
    File('${dir.path}/lib/n.dart').writeAsStringSync('''
// coverage:ignore-start
void a() {}
''');
    final report = File('${dir.path}/coverage/lcov.info')
      ..writeAsStringSync(_lcov(['SF:lib/n.dart', 'DA:2,0']));
    final out = StringBuffer();
    expect(gate([report.path], out), 1);
    expect(
      out.toString(),
      contains('lib/n.dart: coverage:ignore-start without coverage:ignore-end'),
    );
  });
}
