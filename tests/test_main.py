from __future__ import annotations

import runpy
import sys

import pytest

from notelore import update


def test_python_dash_m_notelore_exits_zero(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(sys, "argv", ["notelore"])
    monkeypatch.setattr(update, "hint", lambda: None)
    with pytest.raises(SystemExit) as exc:
        runpy.run_module("notelore", run_name="__main__")
    assert exc.value.code == 0
    assert "Notelore" in capsys.readouterr().out
