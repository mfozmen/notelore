/// A PDF's text through PDFium (pdfrx, #284): native code `flutter test`
/// cannot load, so the chat's checks around it are tested with a fake.
library;

import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

// coverage:ignore-start
/// Every page's text, pages apart by a blank line; throws on a damaged file.
Future<String> nativePdfText(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openData(bytes);
  try {
    return [for (final page in document.pages) (await page.loadText())?.fullText ?? '']
        .join('\n\n');
  } finally {
    await document.dispose();
  }
}
// coverage:ignore-end
