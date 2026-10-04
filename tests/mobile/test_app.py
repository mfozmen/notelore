from __future__ import annotations

import os
import runpy
from collections.abc import Callable
from pathlib import Path

import pytest
import pytest_socket
import toga

from notelore_mobile import app as mobile_app


@pytest.fixture
def sandboxed(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> Callable[[Callable[[], object]], object]:
    """Run app construction with app storage in tmp_path, never the real app data folder.

    The dummy backend creates its asyncio loop while the app is constructed; on
    Windows that loop opens a local socketpair, so sockets are allowed for exactly
    that moment and blocked again right after. No network is involved.
    """
    monkeypatch.delenv("NOTELORE_HOME")
    monkeypatch.setattr(toga.paths.Paths, "data", property(lambda _self: tmp_path / "data"))

    def construct(build: Callable[[], object]) -> object:
        pytest_socket.enable_socket()
        try:
            return build()
        finally:
            pytest_socket.disable_socket()

    return construct


def test_startup_points_notelore_home_at_app_storage(
    sandboxed: Callable[..., object], tmp_path: Path
) -> None:
    sandboxed(mobile_app.main)
    assert os.environ["NOTELORE_HOME"] == str(tmp_path / "data")


def test_the_screen_lists_every_check(sandboxed: Callable[..., object]) -> None:
    notelore = sandboxed(mobile_app.main)
    assert isinstance(notelore, mobile_app.Notelore)
    window = notelore.main_window
    assert isinstance(window, toga.MainWindow)
    box = window.content
    assert isinstance(box, toga.Box)
    labels = [w.text for w in box.children if isinstance(w, toga.Label)]
    assert labels[0] == "Notelore core on this device"
    assert "OK  note round trip: Welcome: 1 entries" in labels
    assert any(line.startswith("OK  HTTPS certificates") for line in labels)
    assert notelore.formal_name == "Notelore"


def test_python_dash_m_starts_the_main_loop(
    sandboxed: Callable[..., object], monkeypatch: pytest.MonkeyPatch
) -> None:
    started: list[bool] = []
    monkeypatch.setattr(mobile_app.Notelore, "main_loop", lambda self: started.append(True))
    sandboxed(lambda: runpy.run_module("notelore_mobile", run_name="__main__"))
    assert started == [True]


def test_results_also_go_to_stdout_for_logcat(
    sandboxed: Callable[..., object], capsys: pytest.CaptureFixture[str]
) -> None:
    sandboxed(mobile_app.main)
    out = capsys.readouterr().out
    assert "notelore-diagnostics: OK  note round trip: Welcome: 1 entries" in out
