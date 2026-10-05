/// What to do with one file during a sync, and how to merge two edited copies.
///
/// Pure functions, no I/O. [decide] implements the decision table in
/// `docs/PLAN.md` over content hashes. [threeWay] merges line by line against
/// the last synced copy (the base): edits in different places merge by themselves,
/// two devices appending at the same spot keep both additions, and only true
/// same-line edits come back as conflicts for a resolver. [autoResolve] settles
/// the one conflict every sync would otherwise hit, the `updated:` date.
///
/// Ported from the Python reference, difflib's matching included: both must cut
/// the same parts for `spec/fixtures/merge.json`.
library;

import 'dart:async';

import 'package:collection/collection.dart';

import '../store/format.dart';
import '../text.dart';

enum SyncAction {
  none,

  /// Upload the local copy.
  push,

  /// Download the remote copy.
  pull,

  /// Both changed: [threeWay], then push the result.
  merge,

  /// Gone remotely, untouched here: move the local copy to history.
  removeLocal,

  /// Gone here (archived), untouched remotely.
  removeRemote,
}

/// The sync action from three content hashes; null means the file is missing there.
SyncAction decide(String? base, String? local, String? remote) {
  if (local == remote) return SyncAction.none;
  if (base == null) {
    // never synced
    if (local == null) return SyncAction.pull;
    return remote == null ? SyncAction.push : SyncAction.merge;
  }
  if (local == base) return remote == null ? SyncAction.removeLocal : SyncAction.pull;
  if (remote == base) return local == null ? SyncAction.removeRemote : SyncAction.push;
  // Both changed. A deletion against a change keeps the change.
  if (local == null) return SyncAction.pull;
  if (remote == null) return SyncAction.push;
  return SyncAction.merge;
}

const _lines = ListEquality<String>();

sealed class MergePart {
  const MergePart();
}

/// Lines both sides agree on after the merge.
final class Clean extends MergePart {
  const Clean(this.lines);

  final List<String> lines;
}

final class Conflict extends MergePart {
  const Conflict(this.base, this.local, this.remote);

  final List<String> base;
  final List<String> local;
  final List<String> remote;

  @override
  bool operator ==(Object other) =>
      other is Conflict &&
      _lines.equals(other.base, base) &&
      _lines.equals(other.local, local) &&
      _lines.equals(other.remote, remote);

  @override
  int get hashCode => Object.hash(_lines.hash(base), _lines.hash(local), _lines.hash(remote));

  @override
  String toString() => 'Conflict(base: $base, local: $local, remote: $remote)';
}

/// The lines that settle a conflict, or null to leave it for the next resolver.
typedef Resolver = FutureOr<List<String>?> Function(Conflict conflict);

/// [Merged.text] could not settle every conflict.
class UnresolvedConflicts implements Exception {
  const UnresolvedConflicts(this.count);

  final int count;

  @override
  String toString() => 'UnresolvedConflicts: $count unresolved conflict(s)';
}

final class Merged {
  const Merged(this.parts);

  final List<MergePart> parts;

  List<Conflict> get conflicts => parts.whereType<Conflict>().toList();

  /// The merged file; every conflict must be settled by [resolve].
  Future<String> text([Resolver? resolve]) async {
    final out = StringBuffer();
    var unresolved = 0;
    for (final part in parts) {
      switch (part) {
        case Clean(:final lines):
          out.writeAll(lines);
        case Conflict():
          final lines = resolve == null ? null : await resolve(part);
          if (lines == null) {
            unresolved++;
          } else {
            out.writeAll(lines);
          }
      }
    }
    if (unresolved > 0) throw UnresolvedConflicts(unresolved);
    return out.toString();
  }
}

/// One side's change: base[start:end] replaced by [lines].
typedef _Hunk = ({int start, int end, List<String> lines, bool local});

Merged threeWay(String base, String local, String remote) {
  final baseLines = splitLines(base, keepEnds: true);
  final hunks = [
    ..._hunks(baseLines, splitLines(local, keepEnds: true), local: true),
    ..._hunks(baseLines, splitLines(remote, keepEnds: true), local: false),
  ];
  // Stable, like Python's sorted: local hunks stay ahead of remote ones at the same spot.
  mergeSort(hunks, compare: (a, b) => a.start != b.start ? a.start - b.start : a.end - b.end);
  final parts = <MergePart>[];
  var position = 0;
  var index = 0;
  while (index < hunks.length) {
    final start = hunks[index].start;
    var end = hunks[index].end;
    final group = [hunks[index++]];
    while (index < hunks.length && _touches(start, end, hunks[index].start, hunks[index].end)) {
      end = end > hunks[index].end ? end : hunks[index].end;
      group.add(hunks[index++]);
    }
    parts
      ..add(Clean(baseLines.sublist(position, start)))
      ..add(_mergeGroup(baseLines, start, end, group, emptyBase: baseLines.isEmpty));
    position = end;
  }
  parts.add(Clean(baseLines.sublist(position)));
  return Merged([
    for (final part in parts)
      if (part is! Clean || part.lines.isNotEmpty) part,
  ]);
}

List<_Hunk> _hunks(List<String> base, List<String> other, {required bool local}) => [
  for (final (i1, i2, j1, j2) in _changes(base, other))
    (start: i1, end: i2, lines: other.sublist(j1, j2), local: local),
];

/// Whether a hunk overlaps the region; hunks that merely abut stay separate.
bool _touches(int start, int end, int hStart, int hEnd) =>
    (start > hStart ? start : hStart) < (end < hEnd ? end : hEnd) ||
    start == hStart ||
    (start < hStart && hStart < end) ||
    (hStart < start && start < hEnd);

/// One side's version of base[start:end] with that side's hunks applied.
List<String> _view(List<String> base, int start, int end, Iterable<_Hunk> hunks) {
  final out = <String>[];
  var position = start;
  for (final hunk in hunks) {
    out
      ..addAll(base.sublist(position, hunk.start))
      ..addAll(hunk.lines);
    position = hunk.end;
  }
  return out..addAll(base.sublist(position, end));
}

MergePart _mergeGroup(
  List<String> base,
  int start,
  int end,
  List<_Hunk> group, {
  required bool emptyBase,
}) {
  final local = group.where((h) => h.local);
  final remote = group.where((h) => !h.local);
  final localView = _view(base, start, end, local);
  final remoteView = _view(base, start, end, remote);
  if (remote.isEmpty || _lines.equals(localView, remoteView)) return Clean(localView);
  if (local.isEmpty) return Clean(remoteView);
  if (start == end && !emptyBase) {
    return Clean([...localView, ...remoteView]); // both appended at the same spot: keep both
  }
  return Conflict(base.sublist(start, end), localView, remoteView);
}

final _updated = RegExp(r'^updated: (\d{4}-\d{2}-\d{2})\n?$');

/// The later `updated:` date wins; any other conflict is left for the next resolver.
List<String>? autoResolve(Conflict conflict) {
  final sides = [conflict.base, conflict.local, conflict.remote];
  if (sides.any((side) => side.length != 1)) return null;
  final matches = [for (final side in sides) _updated.firstMatch(side.single)];
  if (matches.contains(null)) return null;
  final localDate = parseIsoDate(matches[1]![1]!);
  final remoteDate = parseIsoDate(matches[2]![1]!);
  if (localDate == null || remoteDate == null) return null;
  return localDate.isBefore(remoteDate) ? conflict.remote : conflict.local;
}

// ---------------------------------------------------------------- difflib

/// The non-equal opcodes of difflib's `SequenceMatcher(a=a, b=b, autojunk=False)`
/// as (i1, i2, j1, j2): a[i1:i2] becomes b[j1:j2].
List<(int, int, int, int)> _changes(List<String> a, List<String> b) {
  final b2j = <String, List<int>>{};
  for (final (j, line) in b.indexed) {
    b2j.putIfAbsent(line, () => []).add(j);
  }

  /// difflib's find_longest_match without junk: the earliest longest common run.
  /// (Its junk-extension loops cannot extend a run when nothing is junk.)
  (int, int, int) longest(int alo, int ahi, int blo, int bhi) {
    var (besti, bestj, bestsize) = (alo, blo, 0);
    var j2len = <int, int>{};
    for (var i = alo; i < ahi; i++) {
      final next = <int, int>{};
      for (final j in b2j[a[i]] ?? const <int>[]) {
        if (j < blo) continue;
        if (j >= bhi) break;
        final k = next[j] = (j2len[j - 1] ?? 0) + 1;
        if (k > bestsize) (besti, bestj, bestsize) = (i - k + 1, j - k + 1, k);
      }
      j2len = next;
    }
    return (besti, bestj, bestsize);
  }

  final blocks = <(int, int, int)>[];
  final queue = [(0, a.length, 0, b.length)];
  while (queue.isNotEmpty) {
    final (alo, ahi, blo, bhi) = queue.removeLast();
    final (i, j, k) = longest(alo, ahi, blo, bhi);
    if (k == 0) continue;
    blocks.add((i, j, k));
    if (alo < i && blo < j) queue.add((alo, i, blo, j));
    if (i + k < ahi && j + k < bhi) queue.add((i + k, ahi, j + k, bhi));
  }
  blocks
    ..sort((x, y) => x.$1 != y.$1 ? x.$1 - y.$1 : x.$2 - y.$2)
    ..add((a.length, b.length, 0)); // the sentinel closes the last change
  // Adjacent blocks need no collapsing here: only the gaps between them matter.
  final changes = <(int, int, int, int)>[];
  var (i, j) = (0, 0);
  for (final (ai, bj, size) in blocks) {
    if (i < ai || j < bj) changes.add((i, ai, j, bj));
    (i, j) = (ai + size, bj + size);
  }
  return changes;
}
