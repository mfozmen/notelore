from __future__ import annotations

from pathlib import Path

import platformdirs
import pytest

from notelore import paths


def test_notelore_home_overrides_everything(notelore_home: Path) -> None:
    assert paths.notes_dir() == notelore_home / "notes"
    assert paths.state_dir() == notelore_home / "state"


def test_relative_home_resolves_against_cwd(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("NOTELORE_HOME", "sandbox")
    assert paths.notes_dir() == tmp_path / "sandbox" / "notes"
    assert paths.notes_dir().is_absolute()


def test_defaults_without_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NOTELORE_HOME")
    assert paths.notes_dir() == Path.home() / "Notelore"
    assert paths.state_dir() == Path(platformdirs.user_data_dir("notelore"))
