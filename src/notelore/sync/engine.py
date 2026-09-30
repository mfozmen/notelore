"""One sync pass over the notes folder against a remote store.

For every Markdown file under the notes root (``_archive/`` and
``.notelore/history/`` included, so nothing is lost if a device dies), the
engine compares the local copy, the remote copy and the manifest's last synced
state, lets ``merge.decide`` pick the action and carries it out. Nothing is hard
deleted: a file removed on the other device moves to ``.notelore/history/``,
and when the model had to settle a real conflict both original sides go there
too. The manifest is updated file by file, so an interrupted sync keeps its
progress and simply continues next time.

The remote is a small protocol so the Drive client (and a fake in the tests)
plug in the same way.
"""

from __future__ import annotations

import datetime
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

from notelore.store.notes import atomic_write
from notelore.sync.manifest import Entry, Manifest, checked_rel, content_hash
from notelore.sync.merge import Action, Conflict, Resolver, auto_resolve, decide, three_way


@dataclass(frozen=True)
class RemoteFile:
    id: str
    md5: str
    modified: str


class Remote(Protocol):
    def list(self) -> dict[str, RemoteFile]:
        """Every remote file by path relative to the notes root."""
        ...

    def download(self, file_id: str) -> bytes: ...

    def upload(self, rel: str, data: bytes, file_id: str | None) -> RemoteFile:
        """Create the file (``file_id`` None) or replace its content."""
        ...

    def trash(self, file_id: str) -> None:
        """Move to the remote trash: reversible, never a hard delete."""
        ...


@dataclass
class Report:
    pushed: list[str] = field(default_factory=list)
    pulled: list[str] = field(default_factory=list)
    merged: list[str] = field(default_factory=list)
    removed_local: list[str] = field(default_factory=list)
    removed_remote: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)  # unresolved conflict: retried next time
    ignored: list[str] = field(default_factory=list)  # unsafe remote paths
    history: list[str] = field(default_factory=list)  # copies kept under .notelore/history/

    @property
    def changed(self) -> int:
        return sum(
            map(
                len,
                (self.pushed, self.pulled, self.merged, self.removed_local, self.removed_remote),
            )
        )


def sync(
    root: Path,
    manifest: Manifest,
    remote: Remote,
    resolve: Resolver,
    now: datetime.datetime | None = None,
) -> Report:
    stamp = (now or datetime.datetime.now(datetime.UTC)).strftime("%Y-%m-%dT%H%M%SZ")
    local = {p.relative_to(root).as_posix() for p in root.rglob("*.md")} if root.exists() else set()
    remote_files = remote.list()
    report = Report()
    for rel in sorted(local | set(remote_files) | set(manifest.paths())):
        try:
            checked_rel(rel)
        except ValueError:
            report.ignored.append(rel)
            continue
        _Pass(root, manifest, remote, resolve, stamp, report).file(rel, remote_files.get(rel))
    return report


@dataclass
class _Pass:
    root: Path
    manifest: Manifest
    remote: Remote
    resolve: Resolver
    stamp: str
    report: Report

    def _path(self, rel: str, base: Path | None = None) -> Path:
        return (base or self.root).joinpath(*rel.split("/"))

    def _history(self, rel: str) -> Path:
        return self._path(rel, self.root / ".notelore" / "history" / self.stamp)

    def file(self, rel: str, meta: RemoteFile | None) -> None:
        path = self._path(rel)
        local_text = path.read_bytes().decode("utf-8") if path.exists() else None
        entry = self.manifest.get(rel)
        base_hash = entry.local_hash if entry else None
        remote_text: str | None = None
        if meta is None:
            remote_hash = None
        elif entry is not None and meta.md5 == entry.md5:
            remote_hash = base_hash  # untouched since the last sync: no download needed
        else:
            remote_text = self.remote.download(meta.id).decode("utf-8")
            remote_hash = content_hash(remote_text)
        local_hash = content_hash(local_text) if local_text is not None else None
        action = decide(base_hash, local_hash, remote_hash)

        if action is Action.NONE:
            if local_text is not None and meta is not None:
                if entry != Entry(content_hash(local_text), meta.id, meta.md5, meta.modified):
                    self._record(rel, meta, local_text)
            else:  # gone on both sides; it is only listed because the manifest knew it
                self.manifest.forget(rel)
        elif action is Action.PUSH:
            assert local_text is not None
            uploaded = self.remote.upload(
                rel, local_text.encode("utf-8"), meta.id if meta else None
            )
            self._record(rel, uploaded, local_text)
            self.report.pushed.append(rel)
        elif action is Action.PULL:
            assert meta is not None and remote_text is not None
            atomic_write(path, remote_text)
            self._record(rel, meta, remote_text)
            self.report.pulled.append(rel)
        elif action is Action.MERGE:
            assert local_text is not None and meta is not None and remote_text is not None
            self._merge(rel, path, meta, local_text, remote_text)
        elif action is Action.REMOVE_LOCAL:
            target = self._history(rel)
            target.parent.mkdir(parents=True, exist_ok=True)
            path.replace(target)
            self.manifest.forget(rel)
            self.report.removed_local.append(rel)
            self.report.history.append(target.relative_to(self.root).as_posix())
        else:  # Action.REMOVE_REMOTE
            assert meta is not None
            self.remote.trash(meta.id)
            self.manifest.forget(rel)
            self.report.removed_remote.append(rel)

    def _record(self, rel: str, meta: RemoteFile, text: str) -> None:
        self.manifest.record(rel, Entry(content_hash(text), meta.id, meta.md5, meta.modified), text)

    def _merge(
        self, rel: str, path: Path, meta: RemoteFile, local_text: str, remote_text: str
    ) -> None:
        base = self.manifest.base(rel) or ""
        asked_model = False

        def settle(conflict: Conflict) -> list[str] | None:
            nonlocal asked_model
            lines = auto_resolve(conflict)
            if lines is None:
                asked_model = True
                lines = self.resolve(conflict)
            return lines

        try:
            text = three_way(base, local_text, remote_text).text(settle)
        except ValueError:
            self.report.skipped.append(rel)  # nothing written or recorded: retried next time
            return
        if asked_model:  # the losing sides stay available, never silently dropped
            for side, content in (("local", local_text), ("remote", remote_text)):
                kept = self._history(rel)
                kept = kept.with_name(f"{kept.stem}.{side}{kept.suffix}")
                atomic_write(kept, content)
                self.report.history.append(kept.relative_to(self.root).as_posix())
        atomic_write(path, text)
        uploaded = self.remote.upload(rel, text.encode("utf-8"), meta.id)
        self._record(rel, uploaded, text)
        self.report.merged.append(rel)
