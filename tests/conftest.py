from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def notelore_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Point every test at a throwaway NOTELORE_HOME so real notes are never touched."""
    home = tmp_path / "notelore-home"
    home.mkdir()
    monkeypatch.setenv("NOTELORE_HOME", str(home))
    return home
