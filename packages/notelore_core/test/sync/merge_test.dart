import 'package:notelore_core/src/sync/merge.dart';
import 'package:test/test.dart';

const a = 'hash-a', b = 'hash-b', c = 'hash-c';

const base =
    '---\ntitle: T\nupdated: 2026-09-01\n---\n# T\n\n## Notes\n- 2026-09-01: one\n\n## Todo\n';

final unresolved = throwsA(
  isA<UnresolvedConflicts>().having((e) => '$e', 'message', contains('1 unresolved conflict')),
);

void main() {
  group('decision table', () {
    final cases = <(String?, String?, String?, SyncAction)>[
      // nothing to do
      (a, a, a, SyncAction.none),
      (a, b, b, SyncAction.none), // both made the same change
      (null, a, a, SyncAction.none), // first sync, already identical
      (a, null, null, SyncAction.none), // deleted on both sides
      (null, null, null, SyncAction.none),
      // one side changed
      (a, b, a, SyncAction.push),
      (a, a, b, SyncAction.pull),
      (null, a, null, SyncAction.push), // new locally
      (null, null, a, SyncAction.pull), // new remotely
      // both changed
      (a, b, c, SyncAction.merge),
      (null, a, b, SyncAction.merge), // created on both devices before the first sync
      // deleted on one side
      (a, null, a, SyncAction.removeRemote), // deleted (archived) locally, untouched remotely
      (a, a, null, SyncAction.removeLocal),
      (a, null, b, SyncAction.pull), // deleted locally, changed remotely: keep the change
      (a, b, null, SyncAction.push), // changed locally, deleted remotely: keep the change
    ];
    for (final (base, local, remote, action) in cases) {
      test('$base $local $remote -> ${action.name}', () {
        expect(decide(base, local, remote), action);
      });
    }
  });

  test('non-overlapping edits merge cleanly', () async {
    final local = base.replaceFirst(
      '- 2026-09-01: one\n',
      '- 2026-09-01: one\n- 2026-09-02: local\n',
    );
    final remote = base.replaceFirst('## Todo\n', '## Todo\n- [ ] 2026-09-03: remote\n');
    final merged = threeWay(base, local, remote);
    expect(merged.conflicts, isEmpty);
    expect(
      await merged.text(),
      local.replaceFirst('## Todo\n', '## Todo\n- [ ] 2026-09-03: remote\n'),
    );
  });

  test('both appending at the same place keeps both', () async {
    final local = base.replaceFirst(
      '- 2026-09-01: one\n',
      '- 2026-09-01: one\n- 2026-09-02: from laptop\n',
    );
    final remote = base.replaceFirst(
      '- 2026-09-01: one\n',
      '- 2026-09-01: one\n- 2026-09-02: from mac\n',
    );
    final merged = threeWay(base, local, remote);
    expect(merged.conflicts, isEmpty);
    expect(await merged.text(), contains('- 2026-09-02: from laptop\n- 2026-09-02: from mac\n'));
  });

  test('identical changes are not a conflict', () async {
    final same = base.replaceAll('one', 'uno');
    final merged = threeWay(base, same, same);
    expect(merged.conflicts, isEmpty);
    expect(await merged.text(), same);
  });

  test('same-line edits are a conflict until resolved', () async {
    final merged = threeWay(
      base,
      base.replaceAll('one', 'local edit'),
      base.replaceAll('one', 'remote edit'),
    );
    expect(merged.conflicts, [
      Conflict(['- 2026-09-01: one\n'], ['- 2026-09-01: local edit\n'], [
        '- 2026-09-01: remote edit\n',
      ]),
    ]);
    await expectLater(merged.text(), unresolved);
    expect(await merged.text((c) => c.remote), contains('- 2026-09-01: remote edit\n'));
  });

  test('the updated: line is resolved deterministically', () async {
    final local = base
        .replaceAll('updated: 2026-09-01', 'updated: 2026-09-05')
        .replaceFirst('- 2026-09-01: one\n', '- 2026-09-01: one\n- 2026-09-05: laptop\n');
    final remote = base
        .replaceAll('updated: 2026-09-01', 'updated: 2026-09-07')
        .replaceFirst('## Todo\n', '## Todo\n- [ ] 2026-09-07: mac\n');
    final merged = threeWay(base, local, remote);
    expect(merged.conflicts, hasLength(1));
    final text = await merged.text(autoResolve);
    expect(text, contains('updated: 2026-09-07\n'));
    expect(text, allOf(contains('- 2026-09-05: laptop\n'), contains('- [ ] 2026-09-07: mac\n')));
    // the later date wins on either side
    final swapped = await threeWay(base, remote, local).text(autoResolve);
    expect(swapped, contains('updated: 2026-09-07\n'));
  });

  test('autoResolve leaves other conflicts to the next resolver', () {
    expect(autoResolve(Conflict(['a\n'], ['b\n'], ['c\n'])), isNull);
    expect(
      autoResolve(Conflict(['updated: 2026-01-01\n', 'x\n'], ['updated: 2026-01-02\n'], ['y\n'])),
      isNull,
    );
    expect(
      autoResolve(
        Conflict(['updated: 2026-01-01\n'], ['updated: soon\n'], ['updated: 2026-01-02\n']),
      ),
      isNull,
    );
    expect(
      autoResolve(
        Conflict(['updated: 2026-01-01\n'], ['updated: 2026-13-45\n'], ['updated: 2026-01-02\n']),
      ),
      isNull,
    );
  });

  test('a resolver returning null leaves the conflict', () async {
    final merged = threeWay(base, base.replaceAll('one', 'x'), base.replaceAll('one', 'y'));
    await expectLater(merged.text(autoResolve), unresolved);
  });

  test('deletions and edits near each other', () async {
    const base = 'a\nb\nc\nd\ne\n';
    const local = 'a\nc\nd\ne\n'; // deleted b
    expect(await threeWay(base, local, 'a\nb\nc\nd\nE\n').text(), 'a\nc\nd\nE\n');
    // delete vs edit of the same line is a real conflict
    expect(threeWay(base, local, 'a\nB\nc\nd\ne\n').conflicts, [
      Conflict(['b\n'], [], ['B\n']),
    ]);
  });

  test('a first sync with no base merges against empty', () {
    final merged = threeWay('', 'same start\nlocal\n', 'same start\nremote\n');
    expect(merged.conflicts, hasLength(1)); // both "inserted" different whole files
    expect(merged.conflicts.single.base, isEmpty);
  });

  test('text without a trailing newline survives', () async {
    expect(await threeWay('a\nb', 'a\nb', 'a\nB').text(), 'a\nB');
  });

  test('abutting edits on neighbouring lines merge', () async {
    expect(await threeWay('a\nb\nc\nd\n', 'a\nB\nc\nd\n', 'a\nb\nC\nd\n').text(), 'a\nB\nC\nd\n');
  });

  test('only the remote side changed a region', () async {
    expect(await threeWay('a\nb\n', 'a\nb\n', 'a\nX\n').text(), 'a\nX\n');
  });

  test('a longer common run wins over an earlier short one, like difflib', () async {
    // difflib anchors on the longest matching block; "b c d" here, not the first "x".
    const base = 'x\nb\nc\nd\ny\n';
    expect(await threeWay(base, 'b\nc\nd\nx\ny\n', base).text(), 'b\nc\nd\nx\ny\n');
  });

  test('conflicts compare by value', () {
    final conflict = Conflict(['a\n'], ['b\n'], ['c\n']);
    expect(conflict.hashCode, Conflict(['a\n'], ['b\n'], ['c\n']).hashCode);
    expect(conflict, isNot(Conflict(['a\n'], ['b\n'], ['d\n'])));
    expect('$conflict', contains('b'));
  });
}
