/// A PDF's text through PDFium (pdfrx, #284): native code `flutter test`
/// cannot load, so the chat's checks around it are tested with a fake.
library;

import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

// coverage:ignore-start
/// The text of the first [maxPages] pages, apart by a blank line; throws on a
/// damaged file. PDFium runs in pdfrx's own worker, off the UI isolate.
Future<String> nativePdfText(Uint8List bytes, {int maxPages = 200}) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openData(bytes);
  try {
    // What goes to the model is cut far shorter anyway (#389).
    return [
      for (final page in document.pages.take(maxPages)) (await page.loadText())?.fullText ?? '',
    ].join('\n\n');
  } finally {
    await document.dispose();
  }
}
// coverage:ignore-end
