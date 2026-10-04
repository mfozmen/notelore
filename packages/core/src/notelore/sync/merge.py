"""What to do with one file during a sync, and how to merge two edited copies.

Pure functions, no I/O. ``decide`` implements the decision table in
``docs/PLAN.md`` over content hashes. ``three_way`` merges line by line against
the last synced copy (the base): edits in different places merge by themselves,
two devices appending at the same spot keep both additions, and only true
same-line edits come back as conflicts for a resolver. ``auto_resolve`` settles
the one conflict every sync would otherwise hit, the ``updated:`` date.
"""

from __future__ import annotations

import datetime
import enum
import re
from collections.abc import Callable
from dataclasses import dataclass
from difflib import SequenceMatcher


class Action(enum.Enum):
    NONE = "none"
    PUSH = "push"  # upload the local copy
    PULL = "pull"  # download the remote copy
    MERGE = "merge"  # both changed: three_way, then push the result
    REMOVE_LOCAL = "remove_local"  # gone remotely, untouched here: move the local copy to history
    REMOVE_REMOTE = "remove_remote"  # gone here (archived), untouched remotely


def decide(base: str | None, local: str | None, remote: str | None) -> Action:
    """The sync action from three content hashes; None means the file is missing there."""
    if local == remote:
        return Action.NONE
    if base is None:  # never synced
        if local is None:
            return Action.PULL
        return Action.PUSH if remote is None else Action.MERGE
    if local == base:
        return Action.REMOVE_LOCAL if remote is None else Action.PULL
    if remote == base:
        return Action.REMOVE_REMOTE if local is None else Action.PUSH
    # Both changed. A deletion against a change keeps the change.
    if local is None:
        return Action.PULL
    if remote is None:
        return Action.PUSH
    return Action.MERGE


@dataclass(frozen=True)
class Conflict:
    base: list[str]
    local: list[str]
    remote: list[str]


Resolver = Callable[[Conflict], list[str] | None]


@dataclass(frozen=True)
class Merged:
    parts: list[list[str] | Conflict]

    @property
    def conflicts(self) -> list[Conflict]:
        return [p for p in self.parts if isinstance(p, Conflict)]

    def text(self, resolve: Resolver | None = None) -> str:
        """The merged file; every conflict must be settled by ``resolve``."""
        out: list[str] = []
        unresolved = 0
        for part in self.parts:
            if not isinstance(part, Conflict):
                out.extend(part)
                continue
            lines = resolve(part) if resolve else None
            if lines is None:
                unresolved += 1
            else:
                out.extend(lines)
        if unresolved:
            raise ValueError(f"{unresolved} unresolved conflict(s)")
        return "".join(out)


Hunk = tuple[int, int, list[str], str]  # base start, base end, replacement, side


def three_way(base: str, local: str, remote: str) -> Merged:
    base_lines = base.splitlines(keepends=True)
    local_lines = local.splitlines(keepends=True)
    remote_lines = remote.splitlines(keepends=True)
    hunks = sorted(
        _hunks(base_lines, local_lines, "local") + _hunks(base_lines, remote_lines, "remote"),
        key=lambda h: (h[0], h[1]),
    )
    parts: list[list[str] | Conflict] = []
    position = 0
    index = 0
    while index < len(hunks):
        start, end = hunks[index][0], hunks[index][1]
        group = [hunks[index]]
        index += 1
        while index < len(hunks) and _touches(start, end, hunks[index][0], hunks[index][1]):
            end = max(end, hunks[index][1])
            group.append(hunks[index])
            index += 1
        parts.append(base_lines[position:start])
        parts.append(_merge_group(base_lines, start, end, group, empty_base=not base_lines))
        position = end
    parts.append(base_lines[position:])
    return Merged([p for p in parts if p != []])


def _hunks(base: list[str], other: list[str], side: str) -> list[Hunk]:
    matcher = SequenceMatcher(a=base, b=other, autojunk=False)
    return [
        (i1, i2, other[j1:j2], side)
        for tag, i1, i2, j1, j2 in matcher.get_opcodes()
        if tag != "equal"
    ]


def _touches(start: int, end: int, h_start: int, h_end: int) -> bool:
    """Whether a hunk overlaps the region; hunks that merely abut stay separate."""
    return (
        max(start, h_start) < min(end, h_end)
        or start == h_start
        or start < h_start < end
        or h_start < start < h_end
    )


def _view(base: list[str], start: int, end: int, hunks: list[Hunk]) -> list[str]:
    """One side's version of base[start:end] with that side's hunks applied."""
    out: list[str] = []
    position = start
    for h_start, h_end, replacement, _ in hunks:
        out.extend(base[position:h_start])
        out.extend(replacement)
        position = h_end
    out.extend(base[position:end])
    return out


def _merge_group(
    base: list[str], start: int, end: int, group: list[Hunk], empty_base: bool
) -> list[str] | Conflict:
    local = [h for h in group if h[3] == "local"]
    remote = [h for h in group if h[3] == "remote"]
    local_view = _view(base, start, end, local)
    remote_view = _view(base, start, end, remote)
    if not remote or local_view == remote_view:
        return local_view
    if not local:
        return remote_view
    if start == end and not empty_base:
        return local_view + remote_view  # both appended at the same spot: keep both
    return Conflict(base[start:end], local_view, remote_view)


_UPDATED = re.compile(r"^updated: (\d{4}-\d{2}-\d{2})\n?$")


def auto_resolve(conflict: Conflict) -> list[str] | None:
    """The later ``updated:`` date wins; any other conflict is left for the next resolver."""
    sides = (conflict.base, conflict.local, conflict.remote)
    if any(len(side) != 1 for side in sides):
        return None
    matches = [_UPDATED.match(side[0]) for side in sides]
    if not all(matches):
        return None
    try:
        local_date, remote_date = (
            datetime.date.fromisoformat(m.group(1)) for m in matches[1:] if m
        )
    except ValueError:
        return None
    return conflict.local if local_date >= remote_date else conflict.remote
