from __future__ import annotations

import os
import shutil
import sqlite3
import unicodedata
from datetime import date
from pathlib import Path

import pytest

from notelore.store import index, notes
from notelore.store.format import Decision, parse

TODAY = date(2026, 9, 30)


@pytest.fixture(scope="module")
def notes_tree(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Built once per module: every write here is an fsync, which is slow on Windows."""
    root = tmp_path_factory.mktemp("tree") / "notes"
    mopsos = notes.create_note(root, "project", "Mopsos", tags=["investing"], today=TODAY)
    notes.record_decision(mopsos, "database", "PostgreSQL", today=date(2026, 9, 12))
    notes.record_decision(mopsos, "frontend", "React + Vite", today=date(2026, 9, 20))
    notes.record_decision(
        mopsos, "database", "SQLite", reason="Single user, zero setup.", today=date(2026, 9, 28)
    )
    notes.add_entry(mopsos, "Considered adding crypto, postponed.", today=date(2026, 9, 22))
    notes.add_todo(mopsos, "Add Drive backup", due=date(2026, 10, 15), today=TODAY)
    with mopsos.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write("\n## Links\nhand-written zettelkasten link\n")
    sirket = notes.create_note(root, "topic", "Şirket Kuruluşu", lang="tr", today=date(2026, 8, 1))
    notes.add_entry(sirket, "Muhasebeci ile görüşüldü, ücret 2.500 TL.", today=date(2026, 8, 5))
    notes.record_decision(sirket, "Şirket-Türü", "Limited", today=date(2026, 8, 5))
    (root / "topics" / "not-a-note.md").write_text("just some markdown\n", encoding="utf-8")
    (root / "topics" / "latin1.md").write_bytes(b"---\ntitle: caf\xe9\n---\n# x\n")
    (root / "topics" / "odd-date.md").write_text(
        "---\ntitle: Odd\nkind: topic\ncreated: 2026-01-01\nupdated: soon\n---\n# Odd\n",
        encoding="utf-8",
    )
    notes.create_note(root / "_archive" / "2026-01-01", "project", "Old", today=TODAY)
    return root


@pytest.fixture
def root(notes_tree: Path, tmp_path: Path) -> Path:
    return Path(shutil.copytree(notes_tree, tmp_path / "notes"))


HAS_FTS5 = index.fts5_available(sqlite3.connect(":memory:"))


@pytest.fixture(params=["fts5", "like"] if HAS_FTS5 else ["like"])
def idx(
    request: pytest.FixtureRequest, root: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> index.Index:
    if request.param == "like":
        monkeypatch.setattr(index, "fts5_available", lambda _conn: False)
    built = index.Index(tmp_path / "state" / "index.sqlite", root)
    built.rebuild()
    request.addfinalizer(built.close)
    assert built.fts == (request.param == "fts5")
    return built


def test_fts5_probe_reports_the_real_capability() -> None:
    class NoFts5:
        def execute(self, sql: str) -> None:
            raise sqlite3.OperationalError("no such module: fts5")

    assert index.fts5_available(NoFts5()) is False  # type: ignore[arg-type]


def test_list_notes_skips_archive_and_non_notes(idx: index.Index) -> None:
    assert idx.list_notes() == [
        index.NoteInfo("mopsos", "project", "Mopsos", TODAY),
        index.NoteInfo("sirket-kurulusu", "topic", "Şirket Kuruluşu", date(2026, 8, 5)),
        index.NoteInfo("odd-date", "topic", "Odd", None),
    ]
    assert [n.slug for n in idx.list_notes(kind="topic")] == ["sirket-kurulusu", "odd-date"]


def test_get_decision_is_the_newest_active_one(idx: index.Index) -> None:
    assert idx.get_decision("mopsos", "database") == Decision(
        date(2026, 9, 28), "database", "SQLite. Single user, zero setup."
    )
    assert idx.get_decision("mopsos", "hosting") is None
    assert idx.get_decision("nope", "database") is None


def test_lookups_normalize_topic_like_the_writer_does(idx: index.Index) -> None:
    nfd = unicodedata.normalize("NFD", " Şirket-Türü ")
    assert idx.get_decision("sirket-kurulusu", nfd) == Decision(
        date(2026, 8, 5), "şirket-türü", "Limited."
    )
    assert idx.decision_history("sirket-kurulusu", nfd) == [
        idx.get_decision("sirket-kurulusu", nfd)
    ]


def test_same_slug_in_both_kinds_needs_the_kind(idx: index.Index, root: Path) -> None:
    for kind, value in (("project", "Postgres"), ("topic", "Redis")):
        path = notes.create_note(root, kind, "Dup", today=TODAY)
        notes.record_decision(path, "database", value, today=TODAY)
    idx.rebuild()
    with pytest.raises(LookupError, match="project and topic"):
        idx.get_decision("dup", "database")
    with pytest.raises(LookupError, match="project and topic"):
        idx.decision_history("dup")
    assert idx.get_decision("dup", "database", kind="topic") == Decision(
        TODAY, "database", "Redis."
    )
    assert [d.text for d in idx.decision_history("dup", kind="project")] == ["Postgres."]
    assert idx.get_decision("mopsos", "database", kind="topic") is None


def test_decision_history_includes_superseded_in_date_order(idx: index.Index) -> None:
    assert idx.decision_history("mopsos", "database") == [
        Decision(date(2026, 9, 12), "database", "PostgreSQL.", superseded=date(2026, 9, 28)),
        Decision(date(2026, 9, 28), "database", "SQLite. Single user, zero setup."),
    ]
    assert [d.topic for d in idx.decision_history("mopsos")] == ["database", "frontend", "database"]


def test_search_finds_entries_decisions_todos_and_hand_written_lines(idx: index.Index) -> None:
    hits = idx.search("crypto")
    assert [(h.slug, h.section) for h in hits] == [("mopsos", "notes")]
    assert hits[0].text == "Considered adding crypto, postponed."
    assert [h.section for h in idx.search("sqlite")] == ["decisions"]
    assert [h.section for h in idx.search("drive backup")] == ["todo"]
    assert [h.section for h in idx.search("zettelkasten")] == ["Links"]
    assert idx.search("crypto", kind="topic") == []
    assert idx.search("nothing-like-this") == []


def test_search_needs_every_word_in_any_order(idx: index.Index) -> None:
    assert [h.section for h in idx.search("backup drive")] == ["todo"]
    assert idx.search("drive nothing") == []


def test_search_marks_superseded_decisions(idx: index.Index) -> None:
    (old,) = idx.search("postgresql")
    assert old.superseded is True
    (current,) = idx.search("zero setup")
    assert current.superseded is False
    assert idx.search("crypto")[0].superseded is False


def test_search_is_case_and_accent_insensitive_for_turkish(idx: index.Index) -> None:
    assert [h.slug for h in idx.search("MUHASEBECİ")] == ["sirket-kurulusu"]
    assert [h.slug for h in idx.search("görüşüldü")] == ["sirket-kurulusu"]
    assert [h.slug for h in idx.search("gorusuldu")] == ["sirket-kurulusu"]


def test_search_tolerates_query_syntax(idx: index.Index) -> None:
    assert idx.search('crypto "quoted" -x AND OR NOT (') == idx.search("crypto quoted x and or not")
    assert idx.search("%_\\") == []
    assert idx.search("   ") == []


def test_rebuild_is_incremental(
    idx: index.Index, root: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    parsed: list[str] = []

    def counting_parse(text: str) -> object:
        parsed.append(text[:20])
        return parse(text)

    monkeypatch.setattr("notelore.store.index.parse", counting_parse)
    idx.rebuild()
    assert parsed == []  # nothing changed, nothing parsed (not even the non-note file)
    mopsos = root / "projects" / "mopsos.md"
    later = mopsos.stat().st_mtime_ns + 10**9
    os.utime(mopsos, ns=(later, later))  # new mtime, same content
    idx.rebuild()
    assert parsed == []
    notes.add_entry(mopsos, "Now with kubernetes.", today=date(2026, 10, 1))
    idx.rebuild()
    assert len(parsed) == 1
    assert [h.slug for h in idx.search("kubernetes")] == ["mopsos"]
    assert idx.list_notes()[0].updated == date(2026, 10, 1)
    notes.archive_note(root, mopsos, today=date(2026, 10, 1))
    idx.rebuild()
    assert [n.slug for n in idx.list_notes()] == ["sirket-kurulusu", "odd-date"]
    assert idx.get_decision("mopsos", "database") is None
    assert idx.search("kubernetes") == []


def test_index_is_derived_state(idx: index.Index, root: Path, tmp_path: Path) -> None:
    before = (idx.list_notes(), idx.decision_history("mopsos"), idx.search("crypto"))
    idx.close()
    reopened = index.Index(tmp_path / "state" / "index.sqlite", idx.root)
    assert reopened.list_notes() == before[0]  # same backend: the tables survive a reopen
    reopened.close()
    (tmp_path / "state" / "index.sqlite").unlink()
    fresh = index.Index(tmp_path / "state" / "index.sqlite", root)
    fresh.rebuild()
    assert (fresh.list_notes(), fresh.decision_history("mopsos"), fresh.search("crypto")) == before
    fresh.close()


def test_unreadable_files_are_skipped_not_fatal(idx: index.Index, root: Path) -> None:
    assert "latin1" not in [n.slug for n in idx.list_notes()]
    (root / "projects" / "mopsos.md").write_bytes(b"\xff\xfe not utf-8 any more")
    idx.rebuild()
    assert "mopsos" not in [n.slug for n in idx.list_notes()]
    assert idx.search("crypto") == []


@pytest.mark.skipif(not HAS_FTS5, reason="needs an SQLite with FTS5 to switch away from")
def test_reopening_without_fts5_rebuilds_the_derived_tables(
    root: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    db = tmp_path / "state" / "index.sqlite"
    first = index.Index(db, root)
    first.rebuild()
    expected = (first.list_notes(), first.search("crypto"))
    first.close()
    monkeypatch.setattr(index, "fts5_available", lambda _conn: False)
    second = index.Index(db, root)
    assert second.fts is False
    second.rebuild()
    assert (second.list_notes(), second.search("crypto")) == expected
    second.close()


def test_file_that_stops_being_a_note_is_forgotten(idx: index.Index, root: Path) -> None:
    (root / "projects" / "mopsos.md").write_text("# broken now\n", encoding="utf-8")
    idx.rebuild()
    assert [n.slug for n in idx.list_notes()] == ["sirket-kurulusu", "odd-date"]
    assert idx.search("crypto") == []
