/// Repeatable local latency probe. Uses scripted model replies and temp notes;
/// the 200 ms provider wait is illustrative, not a live service measurement.
library;

import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

const _samples = 20;
final _day = DateTime(2026, 10, 17);

class _Provider implements LlmProvider {
  _Provider(this.replies, this.wait);

  final List<AgentResponse> replies;
  final Duration wait;
  var elapsed = Duration.zero;
  var calls = 0;

  @override
  String get model => 'scripted';

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final watch = Stopwatch()..start();
    await Future<void>.delayed(wait);
    final reply = replies[calls++];
    elapsed += watch.elapsed;
    return reply;
  }
}

class _Toolbox extends Toolbox {
  _Toolbox(super.root, super.index) : super(today: _day);

  var elapsed = Duration.zero;
  var calls = 0;

  @override
  String call(String name, Map<String, Object?> args) {
    final watch = Stopwatch()..start();
    final result = super.call(name, args);
    elapsed += watch.elapsed;
    calls++;
    return result;
  }
}

AgentResponse _tool(String name, Map<String, Object?> input) => AgentResponse([
  {'type': 'tool_use', 'id': name, 'name': name, 'input': input},
], 'tool_use');

const _answer = AgentResponse([
  {'type': 'text', 'text': 'Done.'},
], 'end_turn');

Future<({int total, int provider, int tools, int rounds})> _run(
  bool takingNote,
  Duration wait,
  int noteCount,
) async {
  final dir = Directory.systemTemp.createTempSync('notelore_latency_');
  final notes = p.join(dir.path, 'notes');
  final index = NoteIndex(p.join(dir.path, 'index.sqlite'), notes);
  try {
    final path = createNote(notes, 'project', 'Notelore', today: _day);
    addEntry(path, 'The release uses a staged rollout.', today: _day);
    for (var i = 1; i < noteCount; i++) {
      final other = createNote(notes, 'project', 'Project $i', today: _day);
      addEntry(other, 'Project $i has a separate plan.', today: _day);
    }
    final provider = _Provider(
      takingNote
          ? [
              _tool('list_notes', {}),
              _tool('add_note_entry', {
                'slug': 'notelore',
                'text': 'The next release needs a smoke test.',
              }),
              _answer,
            ]
          : [
              _tool('search_notes', {'query': 'staged rollout'}),
              _answer,
            ],
      wait,
    );
    final toolbox = _Toolbox(notes, index);
    final watch = Stopwatch()..start();
    final answer = await Agent(
      provider,
      toolbox,
      today: _day,
    ).ask(takingNote ? 'Note the smoke test for Notelore' : 'What is the rollout plan?');
    watch.stop();
    final expectedRounds = takingNote ? 3 : 2;
    if (answer != 'Done.' ||
        provider.calls != expectedRounds ||
        toolbox.calls != expectedRounds - 1) {
      throw StateError('probe did not exercise the expected agent path');
    }
    return (
      total: watch.elapsedMicroseconds,
      provider: provider.elapsed.inMicroseconds,
      tools: toolbox.elapsed.inMicroseconds,
      rounds: provider.calls,
    );
  } finally {
    index.close();
    _remove(dir);
  }
}

void _remove(Directory dir) {
  if (!p.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path) ||
      !p.basename(dir.path).startsWith('notelore_latency_')) {
    throw StateError('refusing to remove an unexpected probe directory');
  }
  dir.deleteSync(recursive: true);
}

int _median(List<int> values) {
  values.sort();
  return values[values.length ~/ 2];
}

void _largeIndex() {
  final dir = Directory.systemTemp.createTempSync('notelore_latency_');
  final notes = p.join(dir.path, 'notes');
  final index = NoteIndex(p.join(dir.path, 'index.sqlite'), notes);
  try {
    final target = createNote(notes, 'project', 'Notelore', today: _day);
    addEntry(target, 'The release uses a staged rollout.', today: _day);
    for (var i = 1; i < 10000; i++) {
      createNote(notes, 'project', 'Project $i', today: _day);
    }
    final first = Stopwatch()..start();
    index.rebuild();
    first.stop();
    final refreshed = <int>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      index.rebuild();
      refreshed.add(watch.elapsedMilliseconds);
    }
    final search = Stopwatch()..start();
    final result = Toolbox(
      notes,
      index,
      today: _day,
    ).call('search_notes', {'query': 'staged rollout'});
    search.stop();
    if (!result.contains('notelore')) {
      throw StateError('probe search missed its target');
    }
    print(
      jsonEncode({
        'notes': 10000,
        'initialIndexMs': first.elapsedMilliseconds,
        'medianUnchangedRefreshMs': _median(refreshed),
        'searchToolMs': search.elapsedMilliseconds,
      }),
    );
  } finally {
    index.close();
    _remove(dir);
  }
}

Future<void> main(List<String> args) async {
  if (args.contains('--large')) {
    _largeIndex();
    return;
  }
  for (final noteCount in [1, 100]) {
    for (final takingNote in [true, false]) {
      for (final wait in [Duration.zero, const Duration(milliseconds: 200)]) {
        final runs = <({int total, int provider, int tools, int rounds})>[];
        for (var i = 0; i < _samples; i++) {
          runs.add(await _run(takingNote, wait, noteCount));
        }
        int ms(int micros) => (micros / 1000).round();
        print(
          jsonEncode({
            'notes': noteCount,
            'scenario': takingNote ? 'note' : 'retrieval',
            'scriptedProviderWaitMs': wait.inMilliseconds,
            'samples': _samples,
            'providerRounds': runs.first.rounds,
            'medianTotalMs': ms(_median([for (final run in runs) run.total])),
            'medianProviderMs': ms(_median([for (final run in runs) run.provider])),
            'medianToolsMs': ms(_median([for (final run in runs) run.tools])),
            'medianOtherMs': ms(
              _median([for (final run in runs) run.total - run.provider - run.tools]),
            ),
          }),
        );
      }
    }
  }
}
