// The 100% line-coverage gate for the Dart packages (CI and local runs).
//
//   dart run tool/coverage_gate.dart packages/notelore_core/coverage/lcov.info apps/notelore/coverage/lcov.info
//
// Exits non-zero and lists every unhit line when any report is below 100%.
//
// Lines inside `// coverage:ignore-start` ... `// coverage:ignore-end`, or
// ending in `// coverage:ignore-line`, do not count: only for native code that
// `flutter test` cannot load (FFI plugins), kept thin, each with its reason.
import 'dart:io';

/// Unhit line numbers per source file in an lcov report.
Map<String, List<int>> missingLines(String lcov) {
  final missing = <String, List<int>>{};
  String? file;
  for (final line in lcov.split('\n')) {
    if (line.startsWith('SF:')) {
      file = line.substring(3).trim();
    } else if (line.startsWith('DA:') && file != null) {
      final fields = line.substring(3).split(',');
      if (int.parse(fields[1].trim()) == 0) {
        missing.putIfAbsent(file, () => []).add(int.parse(fields[0]));
      }
    }
  }
  return missing;
}

/// The lines of [source] (1-based) that the gate does not count. Throws a
/// [FormatException] for an ignore-start never closed: it would hide the rest.
Set<int> ignoredLines(String source) {
  final ignored = <int>{};
  var inBlock = false;
  for (final (index, line) in source.split('\n').indexed) {
    if (line.contains('coverage:ignore-start')) inBlock = true;
    if (inBlock || line.contains('coverage:ignore-line')) ignored.add(index + 1);
    if (line.contains('coverage:ignore-end')) inBlock = false;
  }
  if (inBlock) {
    throw const FormatException('coverage:ignore-start without coverage:ignore-end');
  }
  return ignored;
}

/// [file]'s ignored lines, the file found relative to the package that owns
/// [report] (`<package>/coverage/lcov.info`) unless it is absolute.
Set<int> _ignoredIn(String file, String report) {
  final path = File(file).isAbsolute ? file : '${File(report).parent.parent.path}/$file';
  try {
    return ignoredLines(File(path).readAsStringSync());
  } on FileSystemException {
    return const {}; // not found: nothing is ignored
  }
}

/// 0 when every report exists and is fully covered, 1 otherwise; findings go to [out].
int gate(List<String> reports, StringSink out) {
  // Keyed by report too: every package writes paths like lib/x.dart, so two
  // reports can name the same relative file and must not hide each other's gaps.
  final missing = <String, List<int>>{};
  for (final report in reports) {
    final file = File(report);
    if (!file.existsSync()) {
      out.writeln('no coverage report at $report');
      return 1;
    }
    for (final entry in missingLines(file.readAsStringSync()).entries) {
      final Set<int> ignored;
      try {
        ignored = _ignoredIn(entry.key, report);
      } on FormatException catch (error) {
        out.writeln('${entry.key}: ${error.message}');
        return 1;
      }
      final left = [
        for (final line in entry.value)
          if (!ignored.contains(line)) line,
      ];
      if (left.isNotEmpty) missing['$report -> ${entry.key}'] = left;
    }
  }
  if (missing.isEmpty) {
    out.writeln('100% line coverage in ${reports.length} report(s)');
    return 0;
  }
  out.writeln('Line coverage below 100%. Unhit lines:');
  for (final entry in missing.entries) {
    out.writeln('  ${entry.key}: ${entry.value.join(', ')}');
  }
  return 1;
}

void main(List<String> arguments) {
  exitCode = gate(arguments, stdout);
}
