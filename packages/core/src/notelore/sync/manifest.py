"""Per-device record of the last synced state, in the state dir.

For every synced file (keyed by its path relative to the notes root, with ``/``):
the local content hash, the Drive file id, Drive's ``md5Checksum`` and
``modifiedTime`` at that moment, and a copy of the content itself: the base for
the next three-way merge. All of it is derived state; losing it only means the
next sync compares everything again.

Keys are case-sensitive while the Windows and macOS file systems are not; the
note slugs are lowercase, so two keys differing only in case do not occur.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
import unicodedata
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from notelore.store.notes import atomic_write


def content_hash(text: str) -> str:
    """SHA-256 of the NFC text as UTF-8; macOS may hand back NFD for the same note."""
    return hashlib.sha256(unicodedata.normalize("NFC", text).encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class Entry:
    local_hash: str
    drive_id: str
    md5: str  # Drive's md5Checksum of the uploaded bytes
    modified: str  # Drive's modifiedTime, RFC 3339 UTC


def checked_rel(rel: str) -> PurePosixPath:
    """``rel`` as a safe relative path: it can come from Drive, so it is untrusted."""
    path = PurePosixPath(rel)
    if (
        not rel
        or "\\" in rel
        or ":" in rel
        or path.is_absolute()
        or any(part in ("", ".", "..") for part in path.parts)
    ):
        raise ValueError(f"not a safe relative path inside the notes folder: {rel!r}")
    return path


def _entry(rel: str, fields: object) -> Entry | None:
    """A loaded entry, or None when its path is unsafe or its fields are not all strings."""
    if not isinstance(fields, dict):
        return None
    try:
        checked_rel(rel)
    except ValueError:
        return None
    names = [f.name for f in dataclasses.fields(Entry)]
    if sorted(fields) != sorted(names) or not all(isinstance(v, str) for v in fields.values()):
        return None
    return Entry(**fields)


class Manifest:
    def __init__(self, state_dir: Path) -> None:
        self._dir = state_dir / "sync"
        self._file = self._dir / "manifest.json"
        self._entries = self._load()

    def _load(self) -> dict[str, Entry]:
        try:
            raw = json.loads(self._file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}  # missing or damaged: derived state, start over
        if not isinstance(raw, dict):
            return {}
        return {rel: entry for rel, fields in raw.items() if (entry := _entry(rel, fields))}

    def _save(self) -> None:
        data = {rel: dataclasses.asdict(e) for rel, e in sorted(self._entries.items())}
        atomic_write(self._file, json.dumps(data, indent=1, ensure_ascii=False) + "\n")

    def _base_file(self, rel: str) -> Path:
        return self._dir / "base" / Path(*checked_rel(rel).parts)

    def paths(self) -> list[str]:
        return sorted(self._entries)

    def get(self, rel: str) -> Entry | None:
        return self._entries.get(rel)

    def base(self, rel: str) -> str | None:
        path = self._base_file(rel)
        try:
            return path.read_text(encoding="utf-8")
        except (OSError, ValueError):  # missing or damaged: no base, the next sync compares all
            return None

    def record(self, rel: str, entry: Entry, content: str) -> None:
        """Remember ``content`` as synced: base copy first, so the manifest never points at none."""
        atomic_write(self._base_file(rel), content)
        self._entries[rel] = entry
        self._save()

    def forget(self, rel: str) -> None:
        base_file = self._base_file(rel)  # validates rel before anything is written
        self._entries.pop(rel, None)
        self._save()
        base_file.unlink(missing_ok=True)
