from __future__ import annotations

import sys
from pathlib import Path

import pytest

from notelore import __version__, update
from notelore.cli import main


def test_version_flag_prints_version(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--version"])
    assert exc.value.code == 0
    assert f"notelore {__version__}" in capsys.readouterr().out


def test_runs_without_arguments_and_shows_the_update_hint(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(update, "hint", lambda: "NEW VERSION HINT")
    assert main([]) == 0
    assert "NEW VERSION HINT" in capsys.readouterr().out


def test_no_hint_when_current(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(update, "hint", lambda: None)
    assert main([]) == 0
    assert "HINT" not in capsys.readouterr().out


def test_update_subcommand(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(update, "run_update", lambda: 7)
    assert main(["update"]) == 7


def test_old_executable_is_cleaned_only_in_a_frozen_build(monkeypatch: pytest.MonkeyPatch) -> None:
    cleaned: list[Path] = []
    monkeypatch.setattr(update, "cleanup", cleaned.append)
    monkeypatch.setattr(update, "hint", lambda: None)
    main([])
    assert cleaned == []
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "executable", "C:/apps/notelore.exe")
    main([])
    assert cleaned == [Path("C:/apps/notelore.exe")]
