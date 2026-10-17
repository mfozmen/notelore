import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/transfer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus/share_plus.dart';

import 'main_test.dart' show FakeFolders;
import 'support.dart';

String fixture(String name) =>
    File(p.join('..', '..', 'spec', 'fixtures', 'notes', name)).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PdfFonts fonts;
  setUpAll(() async => fonts = await PdfFonts.load(rootBundle));

  final mopsos = ('mopsos', fixture('mopsos.md'));
  final turkish = ('sirket-kurulusu', fixture('turkish.md'));

  group('export', () {
    test('Markdown is each note file itself, so it can come back in', () async {
      final files = await exportFiles([mopsos, turkish], ExportFormat.markdown, fonts: fonts);
      expect(files.map((f) => f.name), ['mopsos.md', 'sirket-kurulusu.md']);
      expect(utf8.decode(files[0].bytes), mopsos.$2);
      expect(utf8.decode(files[1].bytes), turkish.$2);
    });

    test('a PDF in Noto Sans, so Turkish letters show; one file for many notes', () async {
      final one = await exportFiles([turkish], ExportFormat.pdf, fonts: fonts);
      expect(one.single.name, 'sirket-kurulusu.pdf');
      final pdf = latin1.decode(one.single.bytes);
      expect(pdf, startsWith('%PDF'));
      expect(pdf, contains('NotoSans')); // the embedded font, not a standard one
      // A loose line without a bullet is laid out as plain text.
      final loose = ('home-server', fixture('multiline-and-loose-lines.md'));
      final many = await exportFiles([mopsos, turkish, loose], ExportFormat.pdf, fonts: fonts);
      expect(many.single.name, 'notelore-notes.pdf');
      expect(many.single.bytes.length, greaterThan(one.single.bytes.length));
    });

    test('a web page for reading anywhere', () async {
      final one = await exportFiles([mopsos], ExportFormat.html, fonts: fonts);
      expect(one.single.name, 'mopsos.html');
      expect(utf8.decode(one.single.bytes), contains('<h1>Mopsos</h1>'));
      final many = await exportFiles([mopsos, turkish], ExportFormat.html, fonts: fonts);
      expect(many.single.name, 'notelore-notes.html');
      expect(utf8.decode(many.single.bytes), contains('Şirket Kuruluşu'));
    });

    test('each format says what it is', () {
      expect(ExportFormat.values.map((f) => f.extension), ['md', 'pdf', 'html']);
    });
  });

  group('exchange', () {
    late Harness harness;
    setUp(() => harness = Harness());
    final file = (name: 'mopsos.md', bytes: Uint8List.fromList(utf8.encode('hi')));

    Exchange exchange({required bool mobile}) => Exchange(
      mobile: mobile,
      share: SharePlus.custom(harness.share),
      scratch: () async => harness.scratch.createTempSync('export'),
    );

    test('a phone hands the files to the share sheet', () async {
      expect(await exchange(mobile: true).send([file], subject: 'Mopsos'), isTrue);
      expect(harness.share.shared.single.subject, 'Mopsos');
      expect(harness.share.contents, {'mopsos.md': utf8.encode('hi')});
      harness.share.status = ShareResultStatus.dismissed;
      expect(await exchange(mobile: true).send([file]), isFalse);
      harness.share.status = ShareResultStatus.unavailable; // Android cannot tell
      expect(await exchange(mobile: true).send([file]), isTrue);
    });

    test('a desktop saves one file where the person says; Cancel saves nothing', () async {
      final at = p.join(harness.scratch.path, 'saved.md');
      expect(await exchange(mobile: false).send([file]), isFalse); // called off
      harness.files.saveAt = at;
      expect(await exchange(mobile: false).send([file]), isTrue);
      expect(harness.files.suggested, ['mopsos.md', 'mopsos.md']);
      expect(File(at).readAsStringSync(), 'hi');
    });

    test('several go into a folder, never over a file already there', () async {
      final other = (name: 'topic.md', bytes: Uint8List.fromList(utf8.encode('t')));
      expect(await exchange(mobile: false).send([file, other]), isFalse); // no folder
      final folder = Directory(p.join(harness.scratch.path, 'out'))..createSync();
      File(p.join(folder.path, 'mopsos.md')).writeAsStringSync('mine');
      harness.files.folder = folder.path;
      expect(await exchange(mobile: false).send([file, other]), isTrue);
      expect(File(p.join(folder.path, 'mopsos.md')).readAsStringSync(), 'mine');
      expect(File(p.join(folder.path, 'mopsos (2).md')).readAsStringSync(), 'hi');
      expect(File(p.join(folder.path, 'topic.md')).readAsStringSync(), 't');
    });

    test('by default the files wait for the share sheet in the app\'s temp folder', () async {
      PathProviderPlatform.instance = FakeFolders(harness.scratch.path);
      final phone = Exchange(mobile: true, share: SharePlus.custom(harness.share));
      expect(await phone.send([file]), isTrue);
      final sent = harness.share.shared.single.files!.single.path;
      expect(p.isWithin(p.join(harness.scratch.path, 'temp'), sent), isTrue);
    });

    test('picks files to import: Markdown on a desktop, anything on a phone', () async {
      final picked = File(p.join(harness.scratch.path, 'mopsos.md'))..writeAsStringSync('hi');
      harness.files.picked = [XFile(picked.path)];
      final desktop = await exchange(mobile: false).pick();
      expect(desktop.single.name, 'mopsos.md');
      expect(utf8.decode(desktop.single.bytes), 'hi');
      expect(harness.files.groups.last!.single.extensions, contains('md'));
      // A phone's apps (a chat download, say) seldom say what a .md is.
      await exchange(mobile: true).pick();
      expect(harness.files.groups.last, isEmpty); // no filter
    });
  });
}
