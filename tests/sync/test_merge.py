from __future__ import annotations

import pytest

from notelore.sync.merge import Action, Conflict, auto_resolve, decide, three_way

A, B, C = "hash-a", "hash-b", "hash-c"


@pytest.mark.parametrize(
    ("base", "local", "remote", "action"),
    [
        # nothing to do
        (A, A, A, Action.NONE),
        (A, B, B, Action.NONE),  # both made the same change
        (None, A, A, Action.NONE),  # first sync, already identical
        (A, None, None, Action.NONE),  # deleted on both sides
        (None, None, None, Action.NONE),
        # one side changed
        (A, B, A, Action.PUSH),
        (A, A, B, Action.PULL),
        (None, A, None, Action.PUSH),  # new locally
        (None, None, A, Action.PULL),  # new remotely
        # both changed
        (A, B, C, Action.MERGE),
        (None, A, B, Action.MERGE),  # created on both devices before the first sync
        # deleted on one side
        (A, None, A, Action.REMOVE_REMOTE),  # deleted (archived) locally, untouched remotely
        (A, A, None, Action.REMOVE_LOCAL),
        (A, None, B, Action.PULL),  # deleted locally, changed remotely: keep the change
        (A, B, None, Action.PUSH),  # changed locally, deleted remotely: keep the change
    ],
)
def test_decision_table(
    base: str | None, local: str | None, remote: str | None, action: Action
) -> None:
    assert decide(base, local, remote) is action


BASE = "---\ntitle: T\nupdated: 2026-09-01\n---\n# T\n\n## Notes\n- 2026-09-01: one\n\n## Todo\n"


def test_non_overlapping_edits_merge_cleanly() -> None:
    local = BASE.replace("- 2026-09-01: one\n", "- 2026-09-01: one\n- 2026-09-02: local\n")
    remote = BASE.replace("## Todo\n", "## Todo\n- [ ] 2026-09-03: remote\n")
    merged = three_way(BASE, local, remote)
    assert merged.conflicts == []
    assert merged.text() == BASE.replace(
        "- 2026-09-01: one\n", "- 2026-09-01: one\n- 2026-09-02: local\n"
    ).replace("## Todo\n", "## Todo\n- [ ] 2026-09-03: remote\n")


def test_both_appending_at_the_same_place_keeps_both() -> None:
    local = BASE.replace("- 2026-09-01: one\n", "- 2026-09-01: one\n- 2026-09-02: from laptop\n")
    remote = BASE.replace("- 2026-09-01: one\n", "- 2026-09-01: one\n- 2026-09-02: from mac\n")
    merged = three_way(BASE, local, remote)
    assert merged.conflicts == []
    assert "- 2026-09-02: from laptop\n- 2026-09-02: from mac\n" in merged.text()


def test_identical_changes_are_not_a_conflict() -> None:
    same = BASE.replace("one", "uno")
    merged = three_way(BASE, same, same)
    assert merged.conflicts == []
    assert merged.text() == same


def test_same_line_edits_are_a_conflict_until_resolved() -> None:
    local = BASE.replace("one", "local edit")
    remote = BASE.replace("one", "remote edit")
    merged = three_way(BASE, local, remote)
    assert merged.conflicts == [
        Conflict(
            ["- 2026-09-01: one\n"], ["- 2026-09-01: local edit\n"], ["- 2026-09-01: remote edit\n"]
        )
    ]
    with pytest.raises(ValueError, match="1 unresolved conflict"):
        merged.text()
    assert "- 2026-09-01: remote edit\n" in merged.text(lambda c: c.remote)


def test_updated_line_is_resolved_deterministically() -> None:
    local = BASE.replace("updated: 2026-09-01", "updated: 2026-09-05").replace(
        "- 2026-09-01: one\n", "- 2026-09-01: one\n- 2026-09-05: laptop\n"
    )
    remote = BASE.replace("updated: 2026-09-01", "updated: 2026-09-07").replace(
        "## Todo\n", "## Todo\n- [ ] 2026-09-07: mac\n"
    )
    merged = three_way(BASE, local, remote)
    assert len(merged.conflicts) == 1
    text = merged.text(auto_resolve)
    assert "updated: 2026-09-07\n" in text
    assert "- 2026-09-05: laptop\n" in text and "- [ ] 2026-09-07: mac\n" in text


def test_auto_resolve_leaves_other_conflicts_to_the_next_resolver() -> None:
    other = Conflict(["a\n"], ["b\n"], ["c\n"])
    assert auto_resolve(other) is None
    two_lines = Conflict(["updated: 2026-01-01\n", "x\n"], ["updated: 2026-01-02\n"], ["y\n"])
    assert auto_resolve(two_lines) is None
    bad_date = Conflict(["updated: 2026-01-01\n"], ["updated: soon\n"], ["updated: 2026-01-02\n"])
    assert auto_resolve(bad_date) is None
    no_such_day = Conflict(
        ["updated: 2026-01-01\n"], ["updated: 2026-13-45\n"], ["updated: 2026-01-02\n"]
    )
    assert auto_resolve(no_such_day) is None


def test_a_resolver_returning_none_leaves_the_conflict() -> None:
    merged = three_way(BASE, BASE.replace("one", "x"), BASE.replace("one", "y"))
    with pytest.raises(ValueError, match="1 unresolved conflict"):
        merged.text(auto_resolve)


def test_deletions_and_edits_near_each_other() -> None:
    base = "a\nb\nc\nd\ne\n"
    local = "a\nc\nd\ne\n"  # deleted b
    remote = "a\nb\nc\nd\nE\n"  # changed e
    assert three_way(base, local, remote).text() == "a\nc\nd\nE\n"
    # delete vs edit of the same line is a real conflict
    merged = three_way(base, local, "a\nB\nc\nd\ne\n")
    assert merged.conflicts == [Conflict(["b\n"], [], ["B\n"])]


def test_first_sync_with_no_base_merges_against_empty() -> None:
    merged = three_way("", "same start\nlocal\n", "same start\nremote\n")
    assert len(merged.conflicts) == 1  # both "inserted" different whole files
    assert merged.conflicts[0].base == []


def test_text_without_trailing_newline_survives() -> None:
    assert three_way("a\nb", "a\nb", "a\nB").text() == "a\nB"
