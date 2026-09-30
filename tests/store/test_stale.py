from __future__ import annotations

from datetime import date
from pathlib import Path

import pytest

from notelore.store import notes
from notelore.store.stale import Stale, find_stale_notes

TODAY = date(2026, 9, 30)


@pytest.fixture
def root(tmp_path: Path) -> Path:
    root = tmp_path / "notes"
    mopsos = notes.create_note(root, "project", "Mopsos", today=date(2026, 1, 1))
    notes.record_decision(mopsos, "database", "PostgreSQL", today=date(2026, 1, 5))
    notes.record_decision(mopsos, "database", "SQLite", today=date(2026, 3, 1))  # supersedes: old
    notes.record_decision(mopsos, "hosting", "Fly", today=date(2026, 9, 1))
    notes.record_decision(mopsos, "hosting", "Hetzner", today=date(2026, 9, 20))  # recent
    text = mopsos.read_text(encoding="utf-8")  # a stray hand-written line must not shift numbers
    notes.atomic_write(mopsos, text.replace("## Decisions\n", "## Decisions\nstray line\n"))
    notes.add_todo(mopsos, "Overdue", due=date(2026, 9, 1), today=date(2026, 8, 1))
    notes.add_todo(mopsos, "Done long ago", due=date(2026, 2, 1), today=date(2026, 2, 1))
    notes.complete_todo(mopsos, 2, today=date(2026, 2, 1))
    notes.add_todo(mopsos, "Future", due=date(2026, 12, 1), today=TODAY)
    fresh = notes.create_note(root, "topic", "Fresh", today=TODAY)
    notes.add_todo(fresh, "Due today is not overdue", due=TODAY, today=TODAY)
    old = notes.create_note(root, "topic", "Untouched", today=date(2026, 1, 1))
    notes.add_entry(old, "written once", today=date(2026, 1, 2))
    (root / "topics" / "not-a-note.md").write_text("plain\n", encoding="utf-8")
    (root / "topics" / "bare.md").write_text(  # no sections, unparsable updated: never stale
        "---\ntitle: Bare\nkind: topic\ncreated: 2026-01-01\nupdated: soon\n---\n# Bare\n",
        encoding="utf-8",
    )
    archive = root / "_archive" / "2026-01-01"
    notes.create_note(archive, "project", "Archived", today=date(2026, 1, 1))
    return root


def test_signals(root: Path) -> None:
    assert find_stale_notes(root, today=TODAY) == [
        Stale("mopsos", "project", "superseded decision", "decisions", 1, date(2026, 3, 1)),
        Stale("mopsos", "project", "overdue todo", "todo", 1, date(2026, 9, 1)),
        Stale("untouched", "topic", "not updated", None, None, date(2026, 1, 2)),
    ]


def test_thresholds_are_tunable(root: Path) -> None:
    stale = find_stale_notes(root, today=TODAY, decision_days=5, file_days=5)
    assert [(s.slug, s.reason, s.number) for s in stale] == [
        ("mopsos", "superseded decision", 1),
        ("mopsos", "superseded decision", 3),
        ("mopsos", "overdue todo", 1),
        ("untouched", "not updated", None),
    ]
    assert find_stale_notes(root, today=date(2027, 12, 1), file_days=10**4) == [
        Stale("mopsos", "project", "superseded decision", "decisions", 1, date(2026, 3, 1)),
        Stale("mopsos", "project", "superseded decision", "decisions", 3, date(2026, 9, 20)),
        Stale("mopsos", "project", "overdue todo", "todo", 1, date(2026, 9, 1)),
        Stale("mopsos", "project", "overdue todo", "todo", 3, date(2026, 12, 1)),
        Stale("fresh", "topic", "overdue todo", "todo", 1, TODAY),
    ]


def test_numbers_match_archive_entries(root: Path) -> None:
    stale = find_stale_notes(root, today=TODAY)
    decision = next(s for s in stale if s.reason == "superseded decision")
    path = notes.note_path(root, decision.kind, decision.slug)
    assert decision.section is not None and decision.number is not None
    notes.archive_entries(root, path, {decision.section: [decision.number]}, today=TODAY)
    assert "PostgreSQL" not in path.read_text(encoding="utf-8")


def test_empty_folder(tmp_path: Path) -> None:
    assert find_stale_notes(tmp_path / "nothing", today=TODAY) == []


def test_a_real_parser_bug_is_not_hidden(root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    def broken(path: Path) -> None:
        raise ValueError("a real bug")

    monkeypatch.setattr("notelore.store.stale.read_note", broken)
    with pytest.raises(ValueError, match="a real bug"):
        find_stale_notes(root, today=TODAY)
