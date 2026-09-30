from __future__ import annotations

import datetime
import hashlib
import os
import unicodedata
from pathlib import Path

import pytest

from notelore.sync.engine import RemoteFile, sync
from notelore.sync.manifest import Manifest
from notelore.sync.merge import Conflict

NOW = datetime.datetime(2026, 10, 1, 9, 30, 5, tzinfo=datetime.UTC)
STAMP = "2026-10-01T093005Z"
NOTE = "---\ntitle: T\nupdated: 2026-09-01\n---\n# T\n\n## Notes\n- 2026-09-01: one\n\n## Todo\n"


class FakeDrive:
    """In-memory Drive: files by relative path, md5 like Drive's md5Checksum."""

    def __init__(self) -> None:
        self.files: dict[str, tuple[str, bytes]] = {}  # rel -> (id, data)
        self.trashed: list[str] = []
        self.uploads = 0
        self._next = 0

    def put(self, rel: str, text: str) -> None:
        file_id = self.files[rel][0] if rel in self.files else self._new_id()
        self.files[rel] = (file_id, text.encode("utf-8"))

    def _new_id(self) -> str:
        self._next += 1
        return f"id{self._next}"

    def text(self, rel: str) -> str:
        return self.files[rel][1].decode("utf-8")

    def list(self) -> dict[str, RemoteFile]:
        return {rel: self._meta(rel) for rel in self.files}

    def _meta(self, rel: str) -> RemoteFile:
        file_id, data = self.files[rel]
        return RemoteFile(file_id, hashlib.md5(data).hexdigest(), f"t{len(data)}")

    def download(self, file_id: str) -> bytes:
        return next(data for fid, data in self.files.values() if fid == file_id)

    def upload(self, rel: str, data: bytes, file_id: str | None) -> RemoteFile:
        self.uploads += 1
        assert file_id is None or self.files[rel][0] == file_id
        self.files[rel] = (file_id or self._new_id(), data)
        return self._meta(rel)

    def trash(self, file_id: str) -> None:
        rel = next(r for r, (fid, _) in self.files.items() if fid == file_id)
        del self.files[rel]
        self.trashed.append(rel)


@pytest.fixture
def root(tmp_path: Path) -> Path:
    return tmp_path / "notes"


@pytest.fixture
def manifest(tmp_path: Path) -> Manifest:
    return Manifest(tmp_path / "state")


def write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


def read(root: Path, rel: str) -> str:
    return (root / rel).read_bytes().decode("utf-8")


def never(conflict: Conflict) -> list[str] | None:
    raise AssertionError("the model must not be asked")


def run(root: Path, manifest: Manifest, drive: FakeDrive, resolver=never):  # type: ignore[no-untyped-def]
    return sync(root, manifest, drive, resolver, now=NOW)


def test_first_sync_pushes_everything_and_the_second_does_nothing(
    root: Path, manifest: Manifest
) -> None:
    write(root, "projects/a.md", NOTE)
    write(root, "_archive/2026-01-01/topics/old.md", NOTE)
    write(root, "notes-outside-kinds.txt", "ignored, not markdown")
    drive = FakeDrive()
    report = run(root, manifest, drive)
    assert report.pushed == ["_archive/2026-01-01/topics/old.md", "projects/a.md"]
    assert drive.text("projects/a.md") == NOTE
    assert manifest.base("projects/a.md") == NOTE
    again = run(root, manifest, drive)
    assert again.changed == 0
    assert drive.uploads == 2


def test_new_remote_file_is_pulled(root: Path, manifest: Manifest) -> None:
    drive = FakeDrive()
    drive.put("topics/from-mac.md", NOTE)
    assert run(root, manifest, drive).pulled == ["topics/from-mac.md"]
    assert read(root, "topics/from-mac.md") == NOTE
    assert manifest.get("topics/from-mac.md") is not None


def test_one_sided_edits_push_or_pull(root: Path, manifest: Manifest) -> None:
    write(root, "projects/a.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    write(root, "projects/a.md", NOTE + "- [ ] 2026-10-01: local\n")
    assert run(root, manifest, drive).pushed == ["projects/a.md"]
    drive.put("projects/a.md", NOTE + "- [ ] 2026-10-01: local\n- [ ] 2026-10-02: remote\n")
    assert run(root, manifest, drive).pulled == ["projects/a.md"]
    assert read(root, "projects/a.md").endswith("- [ ] 2026-10-02: remote\n")


def test_edits_on_both_sides_in_different_places_merge(root: Path, manifest: Manifest) -> None:
    write(root, "projects/a.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    local = NOTE.replace("updated: 2026-09-01", "updated: 2026-09-05").replace(
        "- 2026-09-01: one\n", "- 2026-09-01: one\n- 2026-09-05: laptop\n"
    )
    remote = NOTE.replace("updated: 2026-09-01", "updated: 2026-09-07") + "- [ ] 2026-09-07: mac\n"
    write(root, "projects/a.md", local)
    drive.put("projects/a.md", remote)
    report = run(root, manifest, drive)  # the updated: clash never reaches the model
    assert report.merged == ["projects/a.md"]
    merged = read(root, "projects/a.md")
    assert "updated: 2026-09-07\n" in merged
    assert "- 2026-09-05: laptop\n" in merged and "- [ ] 2026-09-07: mac\n" in merged
    assert drive.text("projects/a.md") == merged
    assert manifest.base("projects/a.md") == merged
    assert report.history == []


def test_a_real_conflict_asks_the_resolver_and_keeps_both_sides(
    root: Path, manifest: Manifest
) -> None:
    write(root, "projects/a.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    write(root, "projects/a.md", NOTE.replace("one", "laptop wording"))
    drive.put("projects/a.md", NOTE.replace("one", "mac wording"))
    asked: list[Conflict] = []

    def pick_remote(conflict: Conflict) -> list[str]:
        asked.append(conflict)
        return conflict.remote

    report = run(root, manifest, drive, pick_remote)
    assert len(asked) == 1
    assert "mac wording" in read(root, "projects/a.md")
    assert "laptop wording" in read(root, f".notelore/history/{STAMP}/projects/a.local.md")
    assert "mac wording" in read(root, f".notelore/history/{STAMP}/projects/a.remote.md")
    assert report.history == [
        f".notelore/history/{STAMP}/projects/a.local.md",
        f".notelore/history/{STAMP}/projects/a.remote.md",
    ]


def test_an_unresolved_conflict_is_skipped_and_retried_later(
    root: Path, manifest: Manifest
) -> None:
    write(root, "projects/a.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    local = NOTE.replace("one", "laptop")
    write(root, "projects/a.md", local)
    drive.put("projects/a.md", NOTE.replace("one", "mac"))
    report = run(root, manifest, drive, lambda conflict: None)
    assert report.skipped == ["projects/a.md"]
    assert read(root, "projects/a.md") == local
    assert "mac" in drive.text("projects/a.md")
    assert manifest.base("projects/a.md") == NOTE  # nothing recorded: the next sync tries again


def test_archiving_locally_trashes_the_remote_copy(root: Path, manifest: Manifest) -> None:
    write(root, "projects/a.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    (root / "projects" / "a.md").unlink()  # what archive_note does, from the sync's point of view
    write(root, "_archive/2026-10-01/projects/a.md", NOTE)
    report = run(root, manifest, drive)
    assert report.removed_remote == ["projects/a.md"]
    assert drive.trashed == ["projects/a.md"]
    assert manifest.get("projects/a.md") is None
    assert "_archive/2026-10-01/projects/a.md" in drive.files


def test_a_remote_removal_moves_the_local_copy_to_history(root: Path, manifest: Manifest) -> None:
    write(root, "topics/t.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    del drive.files["topics/t.md"]
    report = run(root, manifest, drive)
    assert report.removed_local == ["topics/t.md"]
    assert not (root / "topics" / "t.md").exists()
    assert read(root, f".notelore/history/{STAMP}/topics/t.md") == NOTE
    assert manifest.get("topics/t.md") is None


def test_deleted_here_but_changed_there_keeps_the_change(root: Path, manifest: Manifest) -> None:
    write(root, "topics/t.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    (root / "topics" / "t.md").unlink()
    drive.put("topics/t.md", NOTE + "- [ ] 2026-10-01: still wanted\n")
    assert run(root, manifest, drive).pulled == ["topics/t.md"]
    assert "still wanted" in read(root, "topics/t.md")


def test_identical_on_both_sides_without_a_manifest_is_just_recorded(
    root: Path, manifest: Manifest
) -> None:
    write(root, "topics/t.md", NOTE)
    drive = FakeDrive()
    drive.put("topics/t.md", NOTE)
    report = run(root, manifest, drive)
    assert report.changed == 0
    assert drive.uploads == 0
    assert manifest.get("topics/t.md") is not None


def test_unsafe_remote_paths_are_ignored(root: Path, manifest: Manifest, tmp_path: Path) -> None:
    drive = FakeDrive()
    drive.put("../escape.md", NOTE)
    drive.put("topics/fine.md", NOTE)
    report = run(root, manifest, drive)
    assert report.pulled == ["topics/fine.md"]
    assert report.ignored == ["../escape.md"]
    assert not (tmp_path / "escape.md").exists()


def test_gone_on_both_sides_is_forgotten(root: Path, manifest: Manifest) -> None:
    write(root, "topics/t.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    (root / "topics" / "t.md").unlink()
    del drive.files["topics/t.md"]
    report = run(root, manifest, drive)
    assert report.changed == 0
    assert manifest.get("topics/t.md") is None


def test_nfd_local_names_match_nfc_remote_names(root: Path, manifest: Manifest) -> None:
    nfc = unicodedata.normalize("NFC", "topics/café.md")
    write(root, unicodedata.normalize("NFD", nfc), NOTE)
    drive = FakeDrive()
    drive.put(nfc, NOTE)
    report = run(root, manifest, drive)
    assert report.changed == 0
    assert manifest.paths() == [nfc]
    assert list(drive.files) == [nfc]


def test_paths_differing_only_in_case_are_not_touched(root: Path, manifest: Manifest) -> None:
    drive = FakeDrive()
    drive.put("topics/A.md", NOTE)
    drive.put("topics/a.md", NOTE.replace("one", "two"))
    report = run(root, manifest, drive)
    assert report.ignored == ["topics/A.md", "topics/a.md"]
    assert not (root / "topics").exists()


def test_a_file_that_is_not_utf8_is_skipped_not_fatal(root: Path, manifest: Manifest) -> None:
    (root / "topics").mkdir(parents=True)
    (root / "topics" / "latin1.md").write_bytes(b"caf\xe9\n")
    write(root, "topics/fine.md", NOTE)
    drive = FakeDrive()
    drive.files["topics/remote-latin1.md"] = ("r1", b"caf\xe9\n")
    report = run(root, manifest, drive)
    assert report.skipped == ["topics/latin1.md", "topics/remote-latin1.md"]
    assert report.pushed == ["topics/fine.md"]


def test_a_failed_upload_after_a_merge_changes_nothing(
    root: Path, manifest: Manifest, monkeypatch: pytest.MonkeyPatch
) -> None:
    write(root, "projects/a.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    local = NOTE.replace("- 2026-09-01: one\n", "- 2026-09-01: one\n- 2026-09-02: laptop\n")
    write(root, "projects/a.md", local)
    drive.put("projects/a.md", NOTE + "- [ ] 2026-09-03: mac\n")

    def offline(rel: str, data: bytes, file_id: str | None) -> RemoteFile:
        raise OSError("offline")

    monkeypatch.setattr(drive, "upload", offline)
    with pytest.raises(OSError, match="offline"):
        run(root, manifest, drive)
    assert read(root, "projects/a.md") == local
    assert manifest.base("projects/a.md") == NOTE


def test_history_and_archive_files_sync_like_notes(root: Path, manifest: Manifest) -> None:
    write(root, f".notelore/history/{STAMP}/projects/a.local.md", NOTE)
    drive = FakeDrive()
    assert run(root, manifest, drive).pushed == [f".notelore/history/{STAMP}/projects/a.local.md"]


def test_removal_waits_for_a_file_windows_holds(
    root: Path, manifest: Manifest, monkeypatch: pytest.MonkeyPatch
) -> None:
    write(root, "topics/t.md", NOTE)
    drive = FakeDrive()
    run(root, manifest, drive)
    del drive.files["topics/t.md"]
    real_replace = os.replace
    failures: list[object] = []

    def flaky(src: str | os.PathLike[str], dst: str | os.PathLike[str]) -> None:
        if not failures:
            failures.append(dst)
            raise PermissionError("held by Obsidian")
        real_replace(src, dst)

    monkeypatch.setattr(os, "replace", flaky)
    monkeypatch.setattr("time.sleep", lambda _: None)
    assert run(root, manifest, drive).removed_local == ["topics/t.md"]
