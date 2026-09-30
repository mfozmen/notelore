from __future__ import annotations

import sys
from pathlib import Path

import pytest

from notelore import __version__, repl, update
from notelore.cli import main


@pytest.fixture(autouse=True)
def no_repl(monkeypatch: pytest.MonkeyPatch) -> list[bool]:
    started: list[bool] = []

    def run() -> int:
        started.append(True)
        return 3

    monkeypatch.setattr(repl, "run", run)
    return started


def test_version_flag_prints_version(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--version"])
    assert exc.value.code == 0
    assert f"notelore {__version__}" in capsys.readouterr().out


def test_no_arguments_shows_the_update_hint_then_starts_the_repl(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], no_repl: list[bool]
) -> None:
    monkeypatch.setattr(update, "hint", lambda: "NEW VERSION HINT")
    assert main([]) == 3
    assert "NEW VERSION HINT" in capsys.readouterr().out
    assert no_repl == [True]


def test_no_hint_when_current(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(update, "hint", lambda: None)
    main([])
    assert "HINT" not in capsys.readouterr().out


def test_update_subcommand(monkeypatch: pytest.MonkeyPatch, no_repl: list[bool]) -> None:
    monkeypatch.setattr(update, "run_update", lambda: 7)
    assert main(["update"]) == 7
    assert no_repl == []


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
