/// Text helpers that must cut lines exactly like the Python reference.
library;

// Python's str.splitlines boundaries, so both implementations split alike.
final _lineBreak = RegExp('\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]');

/// Python's `text.splitlines(keepends)`: no empty last line for a trailing break.
List<String> splitLines(String text, {bool keepEnds = false}) {
  final lines = <String>[];
  var start = 0;
  for (final match in _lineBreak.allMatches(text)) {
    lines.add(text.substring(start, keepEnds ? match.end : match.start));
    start = match.end;
  }
  if (start < text.length) lines.add(text.substring(start));
  return lines;
}
