from __future__ import annotations

import pytest


@pytest.fixture(autouse=True)
def toga_dummy_backend(monkeypatch: pytest.MonkeyPatch) -> None:
    """Toga picks its backend from TOGA_BACKEND when an app is created; scoped to these tests."""
    monkeypatch.setenv("TOGA_BACKEND", "toga_dummy")
