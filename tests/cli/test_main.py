from __future__ import annotations

import runpy
import sys

import pytest

from notelore_cli import repl, update


def test_python_dash_m_notelore_runs_the_cli(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(sys, "argv", ["notelore"])
    monkeypatch.setattr(update, "hint", lambda: None)
    monkeypatch.setattr(repl, "run", lambda: 0)
    with pytest.raises(SystemExit) as exc:
        runpy.run_module("notelore_cli", run_name="__main__")
    assert exc.value.code == 0
