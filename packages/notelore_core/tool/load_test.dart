/// The notes-at-scale load test (#895): invented notes in a temp folder, timed
/// at 200, 1,000 and 2,000 notes (or the counts given). Prints a Markdown table.
///
///     dart run tool/load_test.dart [count...]
library;

import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/notelore_core.dart';
import 'package:notelore_core/src/sample_notes.dart';
import 'package:path/path.dart' as p;

final _day = DateTime(2026, 10, 18);

/// The median of [runs] calls of [body], in milliseconds.
double _ms(void Function() body, {int runs = 7}) {
  final times = <int>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    body();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  return times[times.length ~/ 2] / 1000;
}

/// Tokens as about four characters each: no tokenizer runs here.
int _tokens(String text) => (text.length / 4).round();

Map<String, Object> _measure(int count) {
  final dir = Directory.systemTemp.createTempSync('notelore_load_');
  final root = p.join(dir.path, 'notes');
  final index = NoteIndex(p.join(dir.path, 'index.sqlite'), root);
  try {
    final notes = sampleNotes(count, newest: _day, days: count);
    for (final MapEntry(:key, :value) in notes.entries) {
      File(p.joinAll([root, ...key.split('/')]))
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    final first = Stopwatch()..start();
    index.rebuild();
    first.stop();
    final toolbox = Toolbox(root, index, today: _day);
    final last = notes.keys.last;
    final (kind, slug) = (
      last.startsWith('projects/') ? 'project' : 'topic',
      p.posix.basenameWithoutExtension(last),
    );
    final list = toolbox.call('list_notes', {});
    var edits = 0;
    final search = toolbox.call('search_notes', {'query': 'garden irrigation supplier'});
    return {
      'notes': count,
      'folder MB': (notes.values.fold(0, (n, t) => n + utf8.encode(t).length) / 1e6),
      'first build ms': first.elapsedMilliseconds,
      'full rescan ms': _ms(
        () => index
          ..invalidateAll()
          ..rebuild(),
      ),
      'one file changed ms': _ms(() {
        File(p.joinAll([root, ...notes.keys.first.split('/')]))
            .writeAsStringSync('${notes.values.first}- ${++edits}\n', flush: true);
        index
          ..invalidateAll()
          ..rebuild();
      }),
      'search_notes ms': _ms(
        () => toolbox.call('search_notes', {'query': 'garden irrigation supplier'}),
      ),
      'listNotes ms': _ms(index.listNotes),
      'relatedTo ms': _ms(() => index.relatedTo(kind, slug)),
      'related_notes ms': _ms(
        () => toolbox.call('related_notes', {
          'title': 'Garden Watering',
          'about': 'a cheaper supplier',
        }),
      ),
      'list_notes tokens': _tokens(list),
      'search_notes tokens': _tokens(search),
      'system prompt tokens': _tokens('${slimSystemPrompt(_day)}\n\n${toolbox.noteList()}'),
    };
  } finally {
    index.close();
    dir.deleteSync(recursive: true);
  }
}

void main(List<String> args) {
  final counts = args.isEmpty ? [200, 1000, 2000] : args.map(int.parse).toList();
  final rows = [for (final count in counts) _measure(count)];
  String cell(Object value) =>
      value is double ? value.toStringAsFixed(value < 10 ? 1 : 0) : '$value';
  print('| ${rows.first.keys.join(' | ')} |');
  print('|${' --: |' * rows.first.length}');
  for (final row in rows) {
    print('| ${row.values.map(cell).join(' | ')} |');
  }
}
