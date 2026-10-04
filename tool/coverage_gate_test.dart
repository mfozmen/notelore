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

  test('a missing report is an error, not a pass', () {
    final out = StringBuffer();
    expect(gate(['does/not/exist.info'], out), 1);
    expect(out.toString(), contains('no coverage report'));
  });
}
