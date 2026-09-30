from __future__ import annotations

import pytest

from notelore import __version__
from notelore.cli import main


def test_version_flag_prints_version(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--version"])
    assert exc.value.code == 0
    assert f"notelore {__version__}" in capsys.readouterr().out


def test_runs_without_arguments() -> None:
    assert main([]) == 0
