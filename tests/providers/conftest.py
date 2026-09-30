"""Fake SDK modules: every provider test runs against these, never the network."""

from __future__ import annotations

import sys
import types
from typing import Any

import pytest


class Recorder:
    """Records the kwargs of the last SDK call and returns a canned response."""

    def __init__(self, response: Any) -> None:
        self.response = response
        self.calls: list[dict[str, Any]] = []
        self.client_kwargs: dict[str, Any] = {}

    def __call__(self, **kwargs: Any) -> Any:
        self.calls.append(kwargs)
        if isinstance(self.response, Exception):
            raise self.response
        return self.response


def ns(**kwargs: Any) -> types.SimpleNamespace:
    return types.SimpleNamespace(**kwargs)


@pytest.fixture
def fake_module(monkeypatch: pytest.MonkeyPatch) -> Any:
    """``fake_module("name", attr=...)`` installs a stand-in for an SDK import."""

    def install(name: str, **attrs: Any) -> types.ModuleType:
        module = types.ModuleType(name)
        for key, value in attrs.items():
            setattr(module, key, value)
        monkeypatch.setitem(sys.modules, name, module)
        return module

    return install


def client_factory(recorder: Recorder, method_path: str) -> type:
    """A fake SDK client class whose ``method_path`` (e.g. "messages.create") is ``recorder``."""

    class Client:
        def __init__(self, **kwargs: Any) -> None:
            recorder.client_kwargs = kwargs
            target: Any = self
            *parents, leaf = method_path.split(".")
            for part in parents:
                setattr(target, part, ns())
                target = getattr(target, part)
            setattr(target, leaf, recorder)

    return Client
