from __future__ import annotations

import os
from datetime import date
from pathlib import Path

import pytest

from notelore.store import notes
from notelore.store.format import Decision, Entry, Raw, Section, Todo

TODAY = date(2026, 9, 30)


@pytest.fixture
def root(tmp_path: Path) -> Path:
    return tmp_path / "notes"


def entries(path: Path, key: str) -> list[object]:
    section = notes.read_note(path).section(key)
    return list((section or Section("")).entries)


# ---------------------------------------------------------------- slugs


@pytest.mark.parametrize(
    ("title", "slug"),
    [
        ("Mopsos", "mopsos"),
        ("Şirket Kuruluşu", "sirket-kurulusu"),
        ("İstanbul'a Taşınma: Plan", "istanbula-tasinma-plan"),
        ("Çığ / Öğle <Üşüme>", "cig-ogle-usume"),
        ("  --Hello   World--  ", "hello-world"),
        ("Café résumé", "cafe-resume"),
        ("CON", "con-note"),
        ("aux.txt", "aux-txt"),
        ("!!!", "untitled"),
        ("a" * 150, "a" * 100),
        ("word " * 40, ("word-" * 20).rstrip("-")),
    ],
)
def test_slugify(title: str, slug: str) -> None:
    assert notes.slugify(title) == slug
    assert notes.slugify(slug) == slug  # idempotent


def test_note_path_per_kind(root: Path) -> None:
    assert notes.note_path(root, "project", "mopsos") == root / "projects" / "mopsos.md"
    assert notes.note_path(root, "topic", "x") == root / "topics" / "x.md"
    with pytest.raises(ValueError, match="kind"):
        notes.note_path(root, "diary", "x")


# ---------------------------------------------------------------- atomic writes


def test_atomic_write_is_utf8_lf_and_leaves_no_temp_file(tmp_path: Path) -> None:
    path = tmp_path / "a" / "n.md"
    notes.atomic_write(path, "# Şükrü\nline\n")
    assert path.read_bytes() == "# Şükrü\nline\n".encode()
    assert [p.name for p in path.parent.iterdir()] == ["n.md"]


def test_atomic_write_retries_when_windows_holds_the_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = tmp_path / "n.md"
    path.write_text("old", encoding="utf-8")
    real_replace = os.replace
    failures: list[object] = []
    naps: list[float] = []

    def flaky_replace(src: str | os.PathLike[str], dst: str | os.PathLike[str]) -> None:
        if len(failures) < 2:
            failures.append(dst)
            raise PermissionError("held by antivirus")
        real_replace(src, dst)

    monkeypatch.setattr(os, "replace", flaky_replace)
    monkeypatch.setattr("time.sleep", naps.append)
    notes.atomic_write(path, "new")
    assert path.read_text(encoding="utf-8") == "new"
    assert len(failures) == 2
    assert naps == [0.05, 0.1]


def test_atomic_write_gives_up_after_retries(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def never(src: str | os.PathLike[str], dst: str | os.PathLike[str]) -> None:
        raise PermissionError("held forever")

    monkeypatch.setattr(os, "replace", never)
    monkeypatch.setattr("time.sleep", lambda _: None)
    with pytest.raises(PermissionError):
        notes.atomic_write(tmp_path / "n.md", "x")
    assert not (tmp_path / "n.md").exists()
    assert list(tmp_path.glob("*.tmp")) == []  # temp file cleaned up


# ---------------------------------------------------------------- create / read / write


def test_create_note_writes_canonical_file(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", tags=["investing"], today=TODAY)
    assert path == root / "projects" / "mopsos.md"
    assert path.read_text(encoding="utf-8") == (
        "---\ntitle: Mopsos\nkind: project\ncreated: 2026-09-30\nupdated: 2026-09-30\n"
        "tags: [investing]\n---\n# Mopsos\n\n## Decisions\n\n## Notes\n\n## Todo\n"
    )


def test_create_note_in_turkish(root: Path) -> None:
    path = notes.create_note(root, "topic", "Şirket", lang="tr", today=TODAY)
    text = path.read_text(encoding="utf-8")
    assert "tags" not in text
    assert text.endswith("# Şirket\n\n## Kararlar\n\n## Notlar\n\n## Yapılacaklar\n")


def test_create_note_refuses_to_overwrite(root: Path) -> None:
    notes.create_note(root, "project", "Mopsos", today=TODAY)
    with pytest.raises(FileExistsError):
        notes.create_note(root, "project", "MOPSOS", today=TODAY)  # same slug


def test_write_note_maintains_updated(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    note = notes.read_note(path)
    notes.write_note(path, note, today=date(2026, 10, 2))
    assert notes.read_note(path).meta["updated"] == date(2026, 10, 2)
    assert notes.read_note(path).meta["created"] == TODAY


# ---------------------------------------------------------------- entries


def test_add_entry_appends_before_the_trailing_blank_line(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    notes.add_entry(path, "Weekly hit rate.", today=TODAY)
    notes.add_entry(path, "Second\nline with\r\nCRLF", today=date(2026, 10, 1))
    text = path.read_text(encoding="utf-8")
    assert (
        "## Notes\n- 2026-09-30: Weekly hit rate.\n- 2026-10-01: Second\n  line with\n  CRLF\n"
        "\n## Todo\n"
    ) in text
    assert "updated: 2026-10-01" in text
    assert entries(path, "notes")[1] == Entry(date(2026, 10, 1), "Second\n  line with\n  CRLF")


@pytest.mark.parametrize(
    ("tail", "expected"),
    [
        ("# Bare\n", "# Bare\n## Notes\n- 2026-09-30: Merhaba\n"),
        ("# Bare\n\n## Kararlar\n", "## Kararlar\n\n## Notlar\n- 2026-09-30: Merhaba\n"),
        ("# Bare\n\n## Kararlar\n\n", "## Kararlar\n\n## Notlar\n- 2026-09-30: Merhaba\n"),
    ],
    ids=["no-sections", "turkish", "already-blank"],
)
def test_add_entry_creates_a_missing_section_in_the_file_language(
    root: Path, tail: str, expected: str
) -> None:
    path = root / "topics" / "bare.md"
    front = "---\ntitle: Bare\nkind: topic\ncreated: 2026-09-01\nupdated: 2026-09-01\n---\n"
    notes.atomic_write(path, front + tail)
    notes.add_entry(path, "Merhaba", today=TODAY)
    assert path.read_text(encoding="utf-8").endswith(expected)


def test_todos(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    notes.add_todo(path, "Set up CI", today=TODAY)
    notes.add_todo(path, "Add Drive backup", due=date(2026, 10, 15), today=TODAY)
    notes.complete_todo(path, 1, today=TODAY)
    assert (
        "## Todo\n- [x] 2026-09-30: Set up CI\n- [ ] 2026-10-15: Add Drive backup\n"
        in path.read_text(encoding="utf-8")
    )
    with pytest.raises(IndexError):
        notes.complete_todo(path, 3, today=TODAY)


def test_record_decision_supersedes_the_active_one_for_the_topic(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    notes.record_decision(path, "database", "PostgreSQL", today=date(2026, 9, 12))
    notes.record_decision(path, "frontend", "React + Vite.", today=date(2026, 9, 20))
    notes.record_decision(
        path, "database", "SQLite", reason="Single user, zero setup.", today=date(2026, 9, 28)
    )
    decisions = [e for e in entries(path, "decisions") if isinstance(e, Decision)]
    assert decisions == [
        Decision(date(2026, 9, 12), "database", "PostgreSQL.", superseded=date(2026, 9, 28)),
        Decision(date(2026, 9, 20), "frontend", "React + Vite."),
        Decision(date(2026, 9, 28), "database", "SQLite. Single user, zero setup."),
    ]
    note = notes.read_note(path)
    assert notes.active_decision(note, "database") == decisions[2]
    assert notes.active_decision(note, "hosting") is None


# ---------------------------------------------------------------- archive


def test_archive_note_moves_the_file_keeping_its_relative_path(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    target = notes.archive_note(root, path, today=TODAY)
    assert target == root / "_archive" / "2026-09-30" / "projects" / "mopsos.md"
    assert not path.exists()
    assert target.read_text(encoding="utf-8").startswith("---\ntitle: Mopsos")
    # the same file archived again the same day: nothing is overwritten
    notes.create_note(root, "project", "Mopsos", today=TODAY)
    assert notes.archive_note(root, path, today=TODAY) == target.with_name("mopsos-2.md")


def test_archive_entries_moves_them_to_the_archive_copy(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    notes.add_entry(path, "keep", today=TODAY)
    notes.add_entry(path, "old one", today=TODAY)
    notes.add_todo(path, "done", today=TODAY)
    notes.complete_todo(path, 1, today=TODAY)
    target = notes.archive_entries(root, path, {"notes": [2], "todo": [1]}, today=TODAY)
    assert target == root / "_archive" / "2026-09-30" / "projects" / "mopsos.md"
    assert [e for e in entries(path, "notes") if isinstance(e, Entry)] == [Entry(TODAY, "keep")]
    assert not any(isinstance(e, Todo) for e in entries(path, "todo"))
    assert notes.read_note(target).title == "Mopsos"
    assert entries(target, "notes")[0] == Entry(TODAY, "old one")
    assert Todo(TODAY, "done", done=True) in entries(target, "todo")
    # a second batch the same day appends to the same archive file
    notes.add_entry(path, "another old", today=TODAY)
    assert notes.archive_entries(root, path, {"notes": [2]}, today=TODAY) == target
    assert Entry(TODAY, "another old") in entries(target, "notes")


def test_archive_entries_rejects_bad_indexes(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    with pytest.raises(IndexError):
        notes.archive_entries(root, path, {"notes": [1]}, today=TODAY)
    with pytest.raises(ValueError, match="section"):
        notes.archive_entries(root, path, {"links": [1]}, today=TODAY)


def test_raw_lines_are_never_archived_as_entries(root: Path) -> None:
    path = notes.create_note(root, "project", "Mopsos", today=TODAY)
    note = notes.read_note(path)
    section = note.section("notes")
    assert section is not None
    section.entries.insert(0, Raw("hand written"))
    notes.write_note(path, note, today=TODAY)
    with pytest.raises(IndexError):
        notes.archive_entries(root, path, {"notes": [1]}, today=TODAY)
