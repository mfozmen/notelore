from __future__ import annotations

import json
from collections.abc import Iterator
from datetime import date
from pathlib import Path
from typing import Any

import pytest

from notelore.store.index import Index
from notelore.tools import Toolbox

TODAY = date(2026, 9, 30)


@pytest.fixture
def box(tmp_path: Path) -> Iterator[Toolbox]:
    root = tmp_path / "notes"
    box = Toolbox(root, Index(tmp_path / "state" / "index.sqlite", root), today=TODAY)
    yield box
    box.index.close()


def call(box: Toolbox, name: str, **args: Any) -> Any:
    text = box.call(name, args)
    try:
        return json.loads(text)
    except ValueError:
        return text


def test_schemas_are_well_formed(box: Toolbox) -> None:
    names = [t.name for t in box.tools]
    assert names == [
        "list_notes",
        "read_note",
        "create_note",
        "add_note_entry",
        "add_todo",
        "complete_todo",
        "record_decision",
        "get_decision",
        "decision_history",
        "search_notes",
        "find_stale_notes",
        "archive",
    ]
    for tool in box.tools:
        assert tool.description
        assert tool.input_schema["type"] == "object"
        for required in tool.input_schema.get("required", []):
            assert required in tool.input_schema["properties"]


def test_create_list_read(box: Toolbox) -> None:
    assert call(box, "create_note", kind="project", title="Mopsos", tags=["investing"]) == {
        "slug": "mopsos",
        "kind": "project",
        "path": "projects/mopsos.md",
    }
    assert call(box, "create_note", kind="topic", title="Şirket", lang="tr")["slug"] == "sirket"
    assert call(box, "list_notes") == [
        {"slug": "mopsos", "kind": "project", "title": "Mopsos", "updated": "2026-09-30"},
        {"slug": "sirket", "kind": "topic", "title": "Şirket", "updated": "2026-09-30"},
    ]
    assert [n["slug"] for n in call(box, "list_notes", kind="topic")] == ["sirket"]
    text = call(box, "read_note", slug="sirket")
    assert text.startswith("---\ntitle: Şirket\n")
    assert "## Kararlar" in text


def test_entries_todos_and_decisions(box: Toolbox) -> None:
    call(box, "create_note", kind="project", title="Mopsos")
    assert call(box, "add_note_entry", slug="mopsos", text="Weekly hit rate.") == "ok"
    assert call(box, "add_todo", slug="mopsos", text="Set up CI") == "ok"
    assert call(box, "add_todo", slug="mopsos", text="Backup", due="2026-10-15") == "ok"
    assert call(box, "complete_todo", slug="mopsos", number=1) == "ok"
    assert call(box, "record_decision", slug="mopsos", topic="database", value="PostgreSQL") == "ok"
    assert (
        call(
            box,
            "record_decision",
            slug="mopsos",
            topic="database",
            value="SQLite",
            reason="Zero setup.",
        )
        == "ok"
    )
    assert call(box, "get_decision", slug="mopsos", topic="database") == {
        "date": "2026-09-30",
        "topic": "database",
        "value": "SQLite",
        "reason": "Zero setup.",
        "superseded": None,
    }
    assert (
        call(box, "get_decision", slug="mopsos", topic="hosting")
        == "No active decision for 'hosting' in 'mopsos'."
    )
    history = call(box, "decision_history", slug="mopsos")
    assert [(d["value"], d["superseded"]) for d in history] == [
        ("PostgreSQL", "2026-09-30"),
        ("SQLite", None),
    ]
    assert call(box, "decision_history", slug="mopsos", topic="nope") == []
    text = call(box, "read_note", slug="mopsos")
    assert "- [x] 2026-09-30: Set up CI\n- [ ] 2026-10-15: Backup\n" in text
    assert "~~2026-09-30 — **database**: PostgreSQL.~~" in text


def test_search_and_stale(box: Toolbox) -> None:
    call(box, "create_note", kind="project", title="Mopsos")
    call(box, "add_note_entry", slug="mopsos", text="Considered adding crypto.")
    call(box, "add_todo", slug="mopsos", text="Old", due="2026-01-01")
    hits = call(box, "search_notes", query="crypto")
    assert hits == [
        {
            "slug": "mopsos",
            "kind": "project",
            "title": "Mopsos",
            "section": "notes",
            "text": "Considered adding crypto.",
            "superseded": False,
        }
    ]
    assert call(box, "search_notes", query="crypto", kind="topic") == []
    assert call(box, "find_stale_notes") == [
        {
            "slug": "mopsos",
            "kind": "project",
            "reason": "overdue todo",
            "section": "todo",
            "number": 1,
            "date": "2026-01-01",
        }
    ]


def test_archive_entries_and_whole_file(box: Toolbox, tmp_path: Path) -> None:
    call(box, "create_note", kind="project", title="Mopsos")
    call(box, "add_note_entry", slug="mopsos", text="keep")
    call(box, "add_note_entry", slug="mopsos", text="old")
    assert call(box, "archive", slug="mopsos", entries={"notes": [2]}) == {
        "archived_to": "_archive/2026-09-30/projects/mopsos.md"
    }
    assert "old" not in call(box, "read_note", slug="mopsos")
    assert call(box, "archive", slug="mopsos") == {
        "archived_to": "_archive/2026-09-30/projects/mopsos-2.md"
    }
    assert call(box, "list_notes") == []
    assert (tmp_path / "notes" / "_archive" / "2026-09-30" / "projects" / "mopsos-2.md").exists()


def test_a_locked_file_is_an_error_message(box: Toolbox, monkeypatch: pytest.MonkeyPatch) -> None:
    call(box, "create_note", kind="project", title="Mopsos")

    def locked(*args: object, **kwargs: object) -> None:
        raise PermissionError("held by another process")

    monkeypatch.setattr("notelore.store.notes.atomic_write", locked)
    assert call(box, "add_note_entry", slug="mopsos", text="x") == "Error: held by another process"


def test_errors_come_back_as_messages_not_exceptions(box: Toolbox, tmp_path: Path) -> None:
    assert call(box, "read_note", slug="nope") == "Error: no note with slug 'nope'."
    outside = tmp_path / "secret.md"
    outside.write_text("private\n", encoding="utf-8")
    for tool, extra in (("read_note", {}), ("add_note_entry", {"text": "x"}), ("archive", {})):
        result = call(box, tool, slug="../../secret", **extra)
        assert result.startswith("Error: invalid slug"), tool
    assert outside.read_text(encoding="utf-8") == "private\n"
    assert call(box, "create_note", kind="diary", title="x").startswith("Error: unknown note kind")
    call(box, "create_note", kind="project", title="Dup")
    call(box, "create_note", kind="topic", title="Dup")
    assert (
        call(box, "read_note", slug="dup")
        == "Error: 'dup' exists as both project and topic; pass kind."
    )
    assert call(box, "read_note", slug="dup", kind="topic").startswith(
        "---\ntitle: Dup\nkind: topic"
    )
    assert call(box, "create_note", kind="project", title="Dup").startswith("Error: ")
    assert call(box, "complete_todo", slug="dup", number=3, kind="topic").startswith("Error: ")
    assert call(box, "add_todo", slug="dup", text="x", due="not-a-date", kind="topic").startswith(
        "Error: "
    )
    assert call(box, "archive", slug="dup", kind="topic", entries={"links": [1]}).startswith(
        "Error: no known section"
    )
    assert call(
        box, "record_decision", slug="dup", kind="topic", topic="a*b", value="x"
    ).startswith("Error: ")
    assert call(box, "get_decision", slug="dup", topic="db").startswith("Error: 'dup' exists as")
    assert call(box, "nonsense") == "Error: unknown tool 'nonsense'."
    assert call(box, "read_note") == "Error: read_note is missing the argument 'slug'."
    assert call(box, "read_note", slug="x", colour="red") == (
        "Error: read_note got an unknown argument 'colour'."
    )
    assert call(box, "complete_todo", slug="dup", number="two", kind="topic") == (
        "Error: complete_todo expects 'number' to be integer, got str."
    )
    assert call(box, "create_note", kind="topic", title="T", tags="not-a-list") == (
        "Error: create_note expects 'tags' to be array, got str."
    )
    assert call(box, "complete_todo", slug="dup", number=True, kind="topic") == (
        "Error: complete_todo expects 'number' to be integer, got bool."
    )
    assert (
        call(box, "add_todo", slug="dup", text="null due is fine", due=None, kind="topic") == "ok"
    )
    assert call(box, "create_note", kind="topic", title="T", tags=["ok", 2]) == (
        "Error: create_note expects every item of 'tags' to be string, got int."
    )
    assert call(box, "archive", slug="dup", kind="topic", entries={"notes": ["one"]}) == (
        "Error: archive expects every item of 'entries.notes' to be integer, got str."
    )
    assert call(box, "archive", slug="dup", kind="topic", entries={"notes": 1}) == (
        "Error: archive expects 'entries.notes' to be array, got int."
    )


def test_a_bug_inside_the_store_is_not_disguised_as_a_tool_error(
    box: Toolbox, monkeypatch: pytest.MonkeyPatch
) -> None:
    call(box, "create_note", kind="project", title="Mopsos")

    def broken(*args: object) -> None:
        raise TypeError("a real bug")

    monkeypatch.setattr("notelore.store.notes.add_entry", broken)
    with pytest.raises(TypeError, match="a real bug"):
        box.call("add_note_entry", {"slug": "mopsos", "text": "x"})
