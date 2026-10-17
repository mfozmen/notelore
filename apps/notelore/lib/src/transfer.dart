/// Notes out of the app and back in (#215): the export formats, the PDF
/// layout, and the [Exchange] that hands files to the share sheet on a phone or
/// to save and open dialogs on the desktop.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

enum ExportFormat {
  /// The note file itself: complete, and importable again.
  markdown('md'),

  /// For reading and printing.
  pdf('pdf'),

  /// A web page, readable on anything with a browser.
  html('html');

  const ExportFormat(this.extension);

  final String extension;
}

/// A file ready to leave the app.
typedef ExportFile = ({String name, Uint8List bytes});

/// The fonts a PDF is set in: Noto Sans has every Turkish letter, the PDF
/// standard fonts do not.
final class PdfFonts {
  const PdfFonts(this.regular, this.bold);

  final pw.Font regular;
  final pw.Font bold;

  static Future<PdfFonts> load(AssetBundle bundle) async => PdfFonts(
    pw.Font.ttf(await bundle.load('assets/fonts/NotoSans-Regular.ttf')),
    pw.Font.ttf(await bundle.load('assets/fonts/NotoSans-Bold.ttf')),
  );
}

/// The name of a file holding several notes.
const _many = 'notelore-notes';

/// [notes] (slug and file text) as files in [format]: Markdown is one file per
/// note, PDF and HTML one file for all of them.
Future<List<ExportFile>> exportFiles(
  List<(String, String)> notes,
  ExportFormat format, {
  required PdfFonts fonts,
}) async {
  final name = '${notes.length == 1 ? notes.single.$1 : _many}.${format.extension}';
  final texts = [for (final (_, text) in notes) text];
  // A project and a topic may share a slug: number the second, never lose it.
  final taken = <String>{};
  String unique(String slug) {
    var name = '$slug.md';
    for (var n = 2; !taken.add(name); n++) {
      name = '$slug ($n).md';
    }
    return name;
  }

  return switch (format) {
    ExportFormat.markdown => [
      for (final (slug, text) in notes) (name: unique(slug), bytes: utf8.encode(text)),
    ],
    ExportFormat.pdf => [(name: name, bytes: await notesPdf(texts, fonts))],
    ExportFormat.html => [(name: name, bytes: utf8.encode(notesHtml('Notelore', texts)))],
  };
}

/// The notes as one PDF, each starting on a new page.
Future<Uint8List> notesPdf(List<String> texts, PdfFonts fonts) {
  final doc = pw.Document(
    title: 'Notelore',
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  for (final text in texts) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (_) => [for (final line in outline(text)) _pdfLine(line)],
      ),
    );
  }
  return doc.save();
}

pw.Widget _pdfLine(OutlineLine line) => switch (line.style) {
  LineStyle.title => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(
      line.text,
      style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
    ),
  ),
  LineStyle.meta => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 12),
    child: pw.Text(line.text, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
  ),
  LineStyle.heading => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
    child: pw.Text(
      line.text,
      style: const pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
    ),
  ),
  LineStyle.item => pw.Bullet(
    text: line.text,
    style: line.struck ? const pw.TextStyle(decoration: pw.TextDecoration.lineThrough) : null,
  ),
  LineStyle.text => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(line.text),
  ),
};

/// A file someone picked to import.
typedef PickedFile = ({String name, Uint8List bytes});

/// Where exports go and imports come from: the share sheet on a phone (so a
/// note can go to WhatsApp or mail, and come back from there), save and open
/// dialogs on the desktop.
class Exchange {
  Exchange({required this.mobile, SharePlus? share, this.scratch = _scratch})
    : _share = share ?? SharePlus.instance;

  final bool mobile;
  final SharePlus _share;

  /// A fresh folder the share sheet can read the files from.
  final Future<Directory> Function() scratch;

  static Future<Directory> _scratch() async =>
      (await getTemporaryDirectory()).createTemp('notelore-export');

  /// Hands [files] on; false when the person called it off.
  Future<bool> send(List<ExportFile> files, {String? subject}) async {
    if (mobile) {
      final folder = await scratch();
      final shared = [
        for (final file in files)
          XFile((File(p.join(folder.path, file.name))..writeAsBytesSync(file.bytes)).path),
      ];
      final result = await _share.share(ShareParams(files: shared, subject: subject));
      return result.status != ShareResultStatus.dismissed;
    }
    if (files.length == 1) {
      final at = await getSaveLocation(suggestedName: files.single.name);
      if (at == null) return false;
      File(at.path).writeAsBytesSync(files.single.bytes);
      return true;
    }
    final folder = await getDirectoryPath();
    if (folder == null) return false;
    for (final file in files) {
      File(_free(folder, file.name)).writeAsBytesSync(file.bytes);
    }
    return true;
  }

  /// [name] in [folder], numbered if a file already has it: never over one.
  static String _free(String folder, String name) {
    var path = p.join(folder, name);
    for (var n = 2; File(path).existsSync(); n++) {
      path = p.join(folder, '${p.basenameWithoutExtension(name)} ($n)${p.extension(name)}');
    }
    return path;
  }

  /// The files the person picks to import; none when called off. A desktop
  /// offers Markdown; a phone anything, as apps seldom say what a .md is.
  /// [any] offers every file everywhere (a chat attachment: its content decides).
  Future<List<PickedFile>> pick({bool any = false}) async {
    final picked = await openFiles(
      acceptedTypeGroups: mobile || any
          ? const []
          : const [
              XTypeGroup(
                label: 'Markdown',
                extensions: ['md', 'markdown', 'txt'],
                uniformTypeIdentifiers: ['net.daringfireball.markdown', 'public.plain-text'],
              ),
            ],
    );
    return [for (final file in picked) (name: file.name, bytes: await file.readAsBytes())];
  }
}
