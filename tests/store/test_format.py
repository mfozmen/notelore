from __future__ import annotations

import unicodedata
from datetime import date
from pathlib import Path

import pytest

from notelore.store.format import Decision, Entry, Raw, Todo, parse, serialize

FIXTURES = sorted((Path(__file__).parent.parent / "fixtures" / "notes").glob("*.md"))
MOPSOS = (Path(__file__).parent.parent / "fixtures" / "notes" / "mopsos.md").read_bytes()


@pytest.mark.parametrize("path", FIXTURES, ids=lambda p: p.name)
def test_round_trip_is_byte_identical(path: Path) -> None:
    raw = path.read_bytes()
    expected = raw.replace(b"\r\n", b"\n")  # CRLF input is normalized to LF on parse
    assert serialize(parse(raw.decode("utf-8"))).encode("utf-8") == expected


def test_crlf_fixture_really_has_crlf() -> None:
    crlf = next(p for p in FIXTURES if p.name.endswith(".crlf.md"))
    assert b"\r\n" in crlf.read_bytes()


def test_front_matter_and_title() -> None:
    note = parse(MOPSOS.decode("utf-8"))
    assert note.meta["title"] == "Mopsos"
    assert note.meta["kind"] == "project"
    assert note.meta["created"] == date(2026, 9, 12)
    assert note.meta["updated"] == date(2026, 9, 30)
    assert note.meta["tags"] == ["investing", "side-project"]
    assert note.title == "Mopsos"


def test_known_sections_are_typed() -> None:
    note = parse(MOPSOS.decode("utf-8"))
    assert [s.key for s in note.sections] == ["decisions", "notes", "todo"]
    decisions = note.section("decisions")
    assert decisions is not None
    first, second, third = (e for e in decisions.entries if isinstance(e, Decision))
    assert first == Decision(
        date(2026, 9, 12), "database", "PostgreSQL.", superseded=date(2026, 9, 28)
    )
    assert first.value == "PostgreSQL"
    assert first.reason is None
    assert second.value == "SQLite"
    assert second.reason == "Single user, zero setup."
    assert second.superseded is None
    assert third.topic == "frontend"

    notes = note.section("notes")
    assert notes is not None
    assert notes.entries[0] == Entry(
        date(2026, 9, 15), "Prediction hit rate is calculated weekly, on Sundays."
    )

    todo = note.section("todo")
    assert todo is not None
    assert todo.entries[0] == Todo(date(2026, 10, 15), "Add Drive backup", done=False)
    assert todo.entries[1] == Todo(date(2026, 9, 25), "Set up CI", done=True)


def test_turkish_headings_map_to_the_same_keys() -> None:
    text = (FIXTURES[0].parent / "turkish.md").read_text(encoding="utf-8")
    note = parse(text)
    assert [s.key for s in note.sections] == ["decisions", "notes", "todo"]
    assert [s.heading for s in note.sections] == ["Kararlar", "Notlar", "Yapılacaklar"]
    decisions = note.section("decisions")
    assert decisions is not None
    assert isinstance(decisions.entries[1], Decision)
    assert decisions.entries[1].topic == "şirket-türü"
    assert decisions.entries[1].value == "Limited şirket"


def test_nfd_input_is_normalized_to_nfc() -> None:
    nfd = unicodedata.normalize("NFD", MOPSOS.decode("utf-8").replace("Mopsos", "Şükrü"))
    note = parse(nfd)
    assert note.title == "Şükrü"
    assert unicodedata.is_normalized("NFC", serialize(note))


def test_unknown_section_is_kept_verbatim_and_empty_section_is_empty() -> None:
    text = (FIXTURES[0].parent / "unknown-and-empty-sections.md").read_text(encoding="utf-8")
    note = parse(text)
    links = note.section("Links")
    assert links is not None
    assert links.key is None
    assert [e.text for e in links.entries if isinstance(e, Raw)] == [
        "Hand-written section, not touched by code.",
        "- https://example.com/a",
        "- https://example.com/b",
        "",
    ]
    todo = note.section("todo")
    assert todo is not None
    assert todo.entries == []


def test_continuation_lines_and_loose_lines() -> None:
    text = (FIXTURES[0].parent / "multiline-and-loose-lines.md").read_text(encoding="utf-8")
    note = parse(text)
    decisions = note.section("decisions")
    assert decisions is not None
    os_, storage = (e for e in decisions.entries if isinstance(e, Decision))
    assert os_.value == "Debian 12"  # no trailing period is tolerated
    assert storage.text == "ZFS mirror. Two 4 TB disks,\n  bought second hand."
    assert storage.value == "ZFS mirror"
    notes = note.section("notes")
    assert notes is not None
    assert isinstance(notes.entries[0], Entry)
    assert notes.entries[0].text.startswith("Reverse proxy is Caddy")
    assert "\n  and is version controlled" in notes.entries[0].text
    assert notes.entries[1] == Raw("Someone typed this without a bullet.")
    todo = note.section("todo")
    assert todo is not None
    assert isinstance(todo.entries[0], Todo)
    assert todo.entries[0].text == "Replace the failing fan\n  (the rear one, 120 mm)"


def test_serialize_writes_canonical_entries() -> None:
    note = parse(MOPSOS.decode("utf-8"))
    decisions = note.section("decisions")
    assert decisions is not None
    decisions.entries.insert(
        -1,
        Decision(date(2026, 9, 30), "hosting", "Fly.io. Cheapest region near users."),
    )
    out = serialize(note)
    assert "- 2026-09-30 — **hosting**: Fly.io. Cheapest region near users.\n" in out
    assert out.endswith("\n")


def test_missing_front_matter_raises() -> None:
    with pytest.raises(ValueError, match="front matter"):
        parse("# No front matter\n")
