"""Every filesystem location Notelore uses. Nothing else may build a path to user data.

``NOTELORE_HOME`` overrides the root for everything (relative values resolve against
the current working directory). Without it, notes live in ``~/Notelore`` (visible on
purpose) and derived state in the per-OS user data dir.
"""

from __future__ import annotations

import os
from pathlib import Path

import platformdirs


def _home() -> Path | None:
    raw = os.environ.get("NOTELORE_HOME")
    return Path(raw).resolve() if raw else None


def notes_dir() -> Path:
    """Root of the Markdown notes tree (projects/, topics/, _archive/, .notelore/)."""
    home = _home()
    return home / "notes" if home else Path.home() / "Notelore"


def state_dir() -> Path:
    """Device-local derived state: search index, sync manifest, merge bases."""
    home = _home()
    return home / "state" if home else Path(platformdirs.user_data_dir("notelore"))
