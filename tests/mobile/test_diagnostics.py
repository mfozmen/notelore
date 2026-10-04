from __future__ import annotations

import sys
from pathlib import Path

import pytest

from notelore_mobile.diagnostics import Check, run


def test_every_check_runs_and_reports(notelore_home: Path) -> None:
    checks = run()
    names = [c.name for c in checks]
    assert names == [
        "note round trip",
        "search index",
        "YAML",
        "HTTPS certificates",
        "desktop-only: keyring",
    ]
    by_name = {c.name: c for c in checks}
    assert by_name["note round trip"].ok
    assert by_name["note round trip"].detail == "Welcome: 1 entries"
    assert not (notelore_home / "notes").exists()  # the check never writes into the user's notes
    assert list((notelore_home / "state").iterdir()) == []  # its scratch folder is gone again
    assert by_name["search index"].ok
    assert by_name["search index"].detail in {"FTS5", "LIKE fallback"}
    assert by_name["YAML"].ok
    assert by_name["HTTPS certificates"].ok
    assert by_name["HTTPS certificates"].detail.endswith("CA certificates")


def test_every_run_starts_from_scratch(notelore_home: Path) -> None:
    run()
    again = {c.name: c for c in run()}
    assert again["note round trip"].detail == "Welcome: 1 entries"


def test_missing_desktop_packages_are_reported_not_fatal(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(sys.modules, "keyring", None)  # None in sys.modules makes the import fail
    by_name = {c.name: c for c in run()}
    assert by_name["desktop-only: keyring"] == Check(
        "desktop-only: keyring", False, "not installed"
    )


def test_a_failing_check_is_captured(monkeypatch: pytest.MonkeyPatch) -> None:
    def broken(*args: object, **kwargs: object) -> None:
        raise OSError("read-only storage")

    monkeypatch.setattr("notelore.store.notes.create_note", broken)
    by_name = {c.name: c for c in run()}
    assert by_name["note round trip"] == Check(
        "note round trip", False, "OSError: read-only storage"
    )
