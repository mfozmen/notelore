from __future__ import annotations

import unicodedata
from pathlib import Path

import pytest

from notelore.sync.manifest import Entry, Manifest, content_hash

ENTRY = Entry(local_hash="h1", drive_id="d1", md5="m1", modified="2026-10-01T10:00:00Z")


def test_content_hash_is_nfc_and_line_ending_stable() -> None:
    nfc = "Şükrü\n"
    assert content_hash(nfc) == content_hash(unicodedata.normalize("NFD", nfc))
    assert content_hash("a\n") != content_hash("a\r\n")  # notes are LF on disk; CRLF is a change
    assert len(content_hash("")) == 64


def test_record_get_base_and_forget(tmp_path: Path) -> None:
    manifest = Manifest(tmp_path / "state")
    assert manifest.get("projects/mopsos.md") is None
    assert manifest.base("projects/mopsos.md") is None
    manifest.record("projects/mopsos.md", ENTRY, "---\ntitle: Şükrü\n---\n")
    assert manifest.get("projects/mopsos.md") == ENTRY
    assert manifest.base("projects/mopsos.md") == "---\ntitle: Şükrü\n---\n"
    assert manifest.paths() == ["projects/mopsos.md"]
    base_file = tmp_path / "state" / "sync" / "base" / "projects" / "mopsos.md"
    assert base_file.read_bytes() == "---\ntitle: Şükrü\n---\n".encode()
    manifest.forget("projects/mopsos.md")
    manifest.forget("projects/mopsos.md")  # already gone: fine
    assert manifest.get("projects/mopsos.md") is None
    assert not base_file.exists()


def test_it_survives_a_restart(tmp_path: Path) -> None:
    Manifest(tmp_path).record("topics/x.md", ENTRY, "x\n")
    again = Manifest(tmp_path)
    assert again.get("topics/x.md") == ENTRY
    assert again.base("topics/x.md") == "x\n"


def test_a_corrupt_manifest_is_derived_state_and_starts_empty(tmp_path: Path) -> None:
    Manifest(tmp_path).record("topics/x.md", ENTRY, "x\n")
    (tmp_path / "sync" / "manifest.json").write_text("{not json", encoding="utf-8")
    assert Manifest(tmp_path).paths() == []
    (tmp_path / "sync" / "manifest.json").write_text('["a list"]', encoding="utf-8")
    assert Manifest(tmp_path).paths() == []


def test_an_entry_with_a_missing_base_copy_has_no_base(tmp_path: Path) -> None:
    manifest = Manifest(tmp_path)
    manifest.record("topics/x.md", ENTRY, "x\n")
    (tmp_path / "sync" / "base" / "topics" / "x.md").unlink()
    assert manifest.base("topics/x.md") is None


@pytest.mark.parametrize(
    "rel", ["../outside.md", "/etc/passwd", "C:/x.md", "topics/../../x.md", "", "topics\\x.md"]
)
def test_relative_paths_from_drive_cannot_escape(tmp_path: Path, rel: str) -> None:
    manifest = Manifest(tmp_path)
    with pytest.raises(ValueError, match="relative path"):
        manifest.record(rel, ENTRY, "x\n")
    with pytest.raises(ValueError, match="relative path"):
        manifest.base(rel)
