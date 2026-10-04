// The 100% line-coverage gate for the Dart packages (CI and local runs).
//
//   dart run tool/coverage_gate.dart packages/notelore_core/coverage/lcov.info apps/notelore/coverage/lcov.info
//
// Exits non-zero and lists every unhit line when any report is below 100%.
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
      missing['$report -> ${entry.key}'] = entry.value;
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
