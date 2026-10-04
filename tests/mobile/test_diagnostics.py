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
        "desktop-only: keyring",
        "desktop-only: LLM SDKs",
    ]
    by_name = {c.name: c for c in checks}
    assert by_name["note round trip"].ok
    assert by_name["note round trip"].detail == "Welcome: 1 entries"
    assert (notelore_home / "notes" / "topics" / "welcome.md").exists()
    assert by_name["search index"].ok
    assert by_name["search index"].detail in {"FTS5", "LIKE fallback"}
    assert by_name["YAML"].ok


def test_a_second_run_reuses_the_note(notelore_home: Path) -> None:
    run()
    again = {c.name: c for c in run()}
    assert again["note round trip"].detail == "Welcome: 2 entries"


def test_missing_desktop_packages_are_reported_not_fatal(monkeypatch: pytest.MonkeyPatch) -> None:
    for module in ("keyring", "anthropic"):  # None in sys.modules makes the import fail
        monkeypatch.setitem(sys.modules, module, None)
    by_name = {c.name: c for c in run()}
    assert by_name["desktop-only: keyring"] == Check(
        "desktop-only: keyring", False, "not installed"
    )
    assert by_name["desktop-only: LLM SDKs"].ok is False


def test_a_failing_check_is_captured(monkeypatch: pytest.MonkeyPatch) -> None:
    def broken(*args: object, **kwargs: object) -> None:
        raise OSError("read-only storage")

    monkeypatch.setattr("notelore.store.notes.create_note", broken)
    by_name = {c.name: c for c in run()}
    assert by_name["note round trip"] == Check(
        "note round trip", False, "OSError: read-only storage"
    )
