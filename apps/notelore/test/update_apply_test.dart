import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/update_apply.dart';
import 'package:path/path.dart' as p;

String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();

void write(String path, String text) =>
    (File(path)..parent.createSync(recursive: true)).writeAsStringSync(text);

void main() {
  late String root;
  late String install;
  late String staging;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('notelore_delta_');
    addTearDown(() => dir.deleteSync(recursive: true));
    root = dir.path;
    install = p.join(root, 'install');
    staging = p.join(root, 'staging');
    Directory(staging).createSync(recursive: true);
  });

  UpdateJob job(Map<String, String> files, {int pid = 1234}) => UpdateJob(
    install: install,
    staging: staging,
    files: files,
    executable: 'notelore.exe',
    parentPid: pid,
  );

  test('copies every staged file, verifies it, and removes the backup', () async {
    write(p.join(install, 'data', 'app.so'), 'old app');
    write(p.join(install, 'notelore.exe'), 'old exe');
    write(p.join(install, '.notelore-backup', 'stale'), 'stale');
    final next = hashOf('new app');
    final exe = hashOf('new exe');
    final fresh = hashOf('new file');
    write(p.join(staging, 'data', 'app.so'), 'new app');
    write(p.join(staging, 'notelore.exe'), 'new exe');
    write(p.join(staging, 'data', 'fresh.txt'), 'new file');

    final logs = <String>[];
    await applyUpdate(
      job({'data/app.so': next, 'notelore.exe': exe, 'data/fresh.txt': fresh}),
      log: logs.add,
    );

    expect(File(p.join(install, 'data', 'app.so')).readAsStringSync(), 'new app');
    expect(File(p.join(install, 'notelore.exe')).readAsStringSync(), 'new exe');
    expect(File(p.join(install, 'data', 'fresh.txt')).readAsStringSync(), 'new file');
    expect(Directory(p.join(install, '.notelore-backup')).existsSync(), isFalse);
    expect(logs, ['updated 3 files']);
  });

  test('a staged file with the wrong hash installs nothing', () async {
    write(p.join(install, 'app.so'), 'old');
    write(p.join(staging, 'app.so'), 'tampered');

    await expectLater(
      applyUpdate(job({'app.so': hashOf('expected')})),
      throwsA(isA<UpdateApplyFailed>()),
    );
    expect(File(p.join(install, 'app.so')).readAsStringSync(), 'old');
    expect(Directory(p.join(install, '.notelore-backup')).existsSync(), isFalse);
  });

  test('a failure halfway puts back the files already copied', () async {
    write(p.join(install, 'a.txt'), 'old a');
    write(p.join(install, 'b.txt'), 'old b');
    write(p.join(install, 'a.txt.update'), 'stale temp');
    write(p.join(staging, 'a.txt'), 'new a');
    write(p.join(staging, 'c.txt'), 'new c');
    // b.txt is missing from the staging folder.

    await expectLater(
      applyUpdate(
        job({'a.txt': hashOf('new a'), 'c.txt': hashOf('new c'), 'b.txt': hashOf('new b')}),
      ),
      throwsA(isA<UpdateApplyFailed>()),
    );
    expect(File(p.join(install, 'a.txt')).readAsStringSync(), 'old a');
    expect(File(p.join(install, 'b.txt')).readAsStringSync(), 'old b');
    expect(File(p.join(install, 'c.txt')).existsSync(), isFalse);
    expect(File(p.join(install, 'a.txt.update')).existsSync(), isFalse);
  });

  test('a missing install or staging folder is refused', () async {
    Directory(staging).createSync(recursive: true);
    await expectLater(applyUpdate(job({})), throwsA(isA<UpdateApplyFailed>()));
    write(p.join(install, 'old'), 'old');
    Directory(staging).deleteSync(recursive: true);
    await expectLater(
      applyUpdate(
        UpdateJob(
          install: install,
          staging: staging,
          files: {'old': hashOf('old')},
          executable: 'notelore.exe',
          parentPid: 1,
        ),
      ),
      throwsA(isA<UpdateApplyFailed>()),
    );
  });

  test('an apply failure names itself', () {
    const error = UpdateApplyFailed('the disk is full');
    expect('$error', 'the disk is full');
  });

  test('a job that is not JSON or has no fields is refused', () {
    for (final text in ['not json', '[]', '{}']) {
      expect(() => UpdateJob.fromJson(text), throwsA(isA<FormatException>()), reason: text);
    }
  });

  test('the job says what it writes and reads back', () {
    final value = job({'data/app.so': hashOf('new')}).toJson();
    final read = UpdateJob.fromJson(jsonEncode(value));
    expect(read.install, install);
    expect(read.staging, staging);
    expect(read.files, {'data/app.so': hashOf('new')});
    expect(read.executable, 'notelore.exe');
    expect(read.parentPid, 1234);
  });

  test('a job with a path out of the folder or a bad hash is refused', () {
    Map<String, Object?> raw({
      String? installPath,
      String? stagingPath,
      Map<String, Object?> files = const {
        'app.so': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
      Object? pid = 1,
      String executable = 'notelore.exe',
    }) => {
      'install': installPath ?? install,
      'staging': stagingPath ?? staging,
      'files': files,
      'executable': executable,
      'parent_pid': pid,
    };

    for (final value in [
      raw(files: {'../app.so': 'a' * 64}),
      raw(files: {'app.so': 'nope'}),
      raw(files: <String, Object?>{}),
      raw(files: {'notelore-updater.exe': 'a' * 64}),
      raw(pid: 0),
      raw(pid: '1'),
      raw(executable: '../notelore.exe'),
      raw(installPath: 'relative'),
      raw(stagingPath: 'relative'),
    ]) {
      expect(
        () => UpdateJob.fromJson(jsonEncode(value)),
        throwsA(isA<FormatException>()),
        reason: '$value',
      );
    }
  });
}
