"""A fake transport: every provider test runs against it, never the network."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import pytest


@dataclass
class Api:
    """Answers ``http.request`` calls from a queue and records them."""

    answers: list[Any] = field(default_factory=list)
    calls: list[dict[str, Any]] = field(default_factory=list)

    def __call__(
        self,
        method: str,
        url: str,
        headers: dict[str, str] | None = None,
        body: Any = None,
        timeout: float = 60.0,
    ) -> Any:
        self.calls.append(
            {
                "method": method,
                "url": url,
                "headers": headers or {},
                "body": body,
                "timeout": timeout,
            }
        )
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer

    @property
    def last(self) -> dict[str, Any]:
        return self.calls[-1]


@pytest.fixture
def api(monkeypatch: pytest.MonkeyPatch) -> Api:
    fake = Api()
    monkeypatch.setattr("notelore.providers.http.request", fake)
    return fake
