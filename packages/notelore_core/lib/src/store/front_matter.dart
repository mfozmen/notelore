/// Reads and writes a note's YAML front matter exactly like the reference (PyYAML).
///
/// Every device writes the same file, so the bytes must not depend on which
/// implementation wrote it: `spec/fixtures/front-matter.json` holds PyYAML's
/// output for the tricky cases and the tests hold this code to it. PyYAML follows
/// YAML 1.1, where a plain `yes` is a boolean and `2026-09-12` a date, so plain
/// scalars are typed here from their source text, not by package:yaml (YAML 1.2).
///
/// Values: String, int, double, bool, null, DateTime (UTC; a date when the time is
/// zero) and lists of those. A nested mapping is read but refused on write rather
/// than written differently from the reference.
library;

import 'dart:collection';

import 'package:yaml/yaml.dart';

final _null = RegExp(r'^(?:~|null|Null|NULL|)$');
final _true = RegExp(r'^(?:yes|Yes|YES|true|True|TRUE|on|On|ON)$');
final _false = RegExp(r'^(?:no|No|NO|false|False|FALSE|off|Off|OFF)$');
final _int = RegExp(
  r'^(?:[-+]?0b[0-1_]+|[-+]?0[0-7_]+|[-+]?(?:0|[1-9][0-9_]*)|[-+]?0x[0-9a-fA-F_]+'
  r'|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$',
);
final _float = RegExp(
  r'^(?:[-+]?(?:[0-9][0-9_]*)\.[0-9_]*(?:[eE][-+][0-9]+)?|\.[0-9][0-9_]*(?:[eE][-+][0-9]+)?'
  r'|[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$',
);
final _timestamp = RegExp(
  r'^(?:([0-9]{4})-([0-9]{2})-([0-9]{2})'
  r'|([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?:[Tt]|[ \t]+)([0-9]{1,2}):([0-9]{2}):([0-9]{2}))$',
);
final _special = RegExp(r'^(?:<<|=)$'); // merge and value keys: never plain strings

/// The front matter as an ordered map. Throws [FormatException] for invalid YAML
/// or a document that is not a mapping; an empty document is an empty map.
Map<String, Object?> loadFrontMatter(String text) {
  final YamlNode document;
  try {
    document = loadYamlNode(text);
  } on YamlException catch (error) {
    throw FormatException('invalid YAML front matter: ${error.message}');
  }
  if (document is YamlScalar && document.value == null) return {};
  if (document is! YamlMap) throw const FormatException('front matter must be a mapping');
  return _map(document);
}

Map<String, Object?> _map(YamlMap map) => LinkedHashMap.of({
  for (final MapEntry(:key, :value) in map.nodes.entries)
    '${_value(key as YamlNode)}': _value(value),
});

Object? _value(YamlNode node) => switch (node) {
  final YamlMap map => _map(map),
  final YamlList list => [for (final item in list.nodes) _value(item)],
  final YamlScalar scalar when scalar.style == ScalarStyle.PLAIN => _resolve(scalar.span.text),
  _ => node.value, // a quoted scalar: always the string as written
};

/// PyYAML's implicit typing of a plain scalar.
Object? _resolve(String text) {
  if (_null.hasMatch(text)) return null;
  if (_true.hasMatch(text)) return true;
  if (_false.hasMatch(text)) return false;
  if (_int.hasMatch(text)) return _parseInt(text);
  if (_float.hasMatch(text)) return _parseFloat(text);
  final stamp = _timestamp.firstMatch(text);
  if (stamp != null) return _parseTimestamp(stamp);
  return text;
}

int _parseInt(String text) {
  var digits = text.replaceAll('_', '');
  var sign = 1;
  if (digits.startsWith('-') || digits.startsWith('+')) {
    sign = digits.startsWith('-') ? -1 : 1;
    digits = digits.substring(1);
  }
  final value = digits.contains(':')
      ? digits.split(':').fold(0, (total, part) => total * 60 + int.parse(part))
      : digits.startsWith('0b')
      ? int.parse(digits.substring(2), radix: 2)
      : digits.startsWith('0x')
      ? int.parse(digits.substring(2), radix: 16)
      : digits.length > 1 && digits.startsWith('0')
      ? int.parse(digits.substring(1), radix: 8)
      : int.parse(digits);
  return sign * value;
}

double _parseFloat(String text) {
  final lower = text.replaceAll('_', '').toLowerCase();
  if (lower.endsWith('.nan')) return double.nan;
  if (lower.endsWith('.inf')) {
    return lower.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  return double.parse(lower);
}

DateTime _parseTimestamp(RegExpMatch m) {
  int at(int group) => int.parse(m.group(group)!);
  if (m.group(1) != null) return DateTime.utc(at(1), at(2), at(3));
  return DateTime.utc(at(4), at(5), at(6), at(7), at(8), at(9));
}

/// The front matter as PyYAML writes it with one `safe_dump` per key: scalars in
/// block style, lists in flow style, no line folding.
String dumpFrontMatter(Map<String, Object?> meta) => meta.entries
    .map((entry) => '${_string(entry.key, flow: false)}: ${_dump(entry.value)}\n')
    .join();

String _dump(Object? value) => switch (value) {
  final List<Object?> list => '[${list.map(_flowItem).join(', ')}]',
  _ => _scalar(value, flow: false),
};

String _flowItem(Object? item) => _scalar(item, flow: true);

String _scalar(Object? value, {required bool flow}) => switch (value) {
  null => 'null',
  final bool flag => '$flag',
  final int number => '$number',
  final double number => _float_(number),
  final DateTime time => _time(time),
  final String text => _string(text, flow: flow),
  _ => throw UnsupportedError(
    'front matter value ${value.runtimeType} is not written; only scalars and flat lists are',
  ),
};

String _float_(double value) {
  if (value.isNaN) return '.nan';
  if (value.isInfinite) return value.isNegative ? '-.inf' : '.inf';
  return '$value';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _time(DateTime t) {
  final date = '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';
  if (t.hour == 0 && t.minute == 0 && t.second == 0) return date;
  return '$date ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

String _string(String text, {required bool flow}) {
  if (text.isEmpty) return "''";
  if (_needsDoubleQuotes(text)) return _doubleQuoted(text);
  if (_needsQuotes(text, flow: flow)) return "'${text.replaceAll("'", "''")}'";
  return text;
}

/// Characters PyYAML cannot write plain or single-quoted (allow_unicode=True).
/// Line breaks are included: front-matter values are single-line.
bool _isSpecial(int c) =>
    c < 0x20 ||
    (c >= 0x7F && c <= 0x9F) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0xFEFF ||
    (c >= 0xD800 && c <= 0xDFFF) ||
    c == 0xFFFE ||
    c == 0xFFFF;

bool _needsDoubleQuotes(String text) => text.runes.any(_isSpecial);

/// PyYAML's ESCAPE_REPLACEMENTS.
const _escapes = {
  0x00: r'\0',
  0x07: r'\a',
  0x08: r'\b',
  0x09: r'\t',
  0x0A: r'\n',
  0x0B: r'\v',
  0x0C: r'\f',
  0x0D: r'\r',
  0x1B: r'\e',
  0x22: r'\"',
  0x5C: r'\\',
  0x85: r'\N',
  0x2028: r'\L',
  0x2029: r'\P',
};

String _doubleQuoted(String text) {
  final out = StringBuffer('"');
  for (final c in text.runes) {
    final named = _escapes[c];
    if (named != null) {
      out.write(named);
    } else if (_isSpecial(c)) {
      final hex = c.toRadixString(16).toUpperCase();
      out.write(c <= 0xFF ? '\\x${hex.padLeft(2, '0')}' : '\\u${hex.padLeft(4, '0')}');
    } else {
      out.writeCharCode(c);
    }
  }
  return (out..write('"')).toString();
}

/// PyYAML's analyze_scalar, for the single-line strings front matter holds.
bool _needsQuotes(String text, {required bool flow}) {
  if (_resolve(text) is! String || _special.hasMatch(text)) return true;
  if (text.startsWith(' ') || text.endsWith(' ')) return true;
  if (text.startsWith('---') || text.startsWith('...')) return true;
  final first = text[0];
  final firstFollowedBySpace = text.length == 1 || text[1] == ' ';
  if ('#,[]{}&*!|>\'"%@`'.contains(first)) return true;
  if ('?:'.contains(first) && (flow || firstFollowedBySpace)) return true;
  if (first == '-' && firstFollowedBySpace) return true;
  final rest = text.substring(1);
  if (text.contains(' #')) return true;
  if (rest.contains(': ') || text.endsWith(':')) return true;
  if (flow && RegExp(r'[,?\[\]{}:]').hasMatch(rest)) return true;
  return false;
}
