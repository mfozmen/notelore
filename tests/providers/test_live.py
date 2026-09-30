"""Opt-in checks against the real services: ``uv run pytest -m live``.

Each test needs its key in the environment (``NOTELORE_<PROVIDER>_API_KEY``) or,
for Ollama, a running daemon; otherwise it is skipped.
"""

from __future__ import annotations

import os

import pytest

from notelore import secrets
from notelore.providers import create_provider, find
from notelore.providers.validator import validate_key

pytestmark = [pytest.mark.live, pytest.mark.enable_socket]


@pytest.mark.parametrize("name", ["anthropic", "openai", "gemini", "ollama"])
def test_key_validates_and_one_turn_answers(name: str) -> None:
    spec = find(name)
    key = secrets.load_key(name) if spec.requires_api_key else ""
    if spec.requires_api_key and not key:
        pytest.skip(f"{secrets.env_var(name)} not set")
    if name == "ollama" and not os.environ.get("NOTELORE_LIVE_OLLAMA"):
        pytest.skip("NOTELORE_LIVE_OLLAMA not set")
    validate_key(spec, key or "")
    response = create_provider(spec, key).turn(
        "Answer with one word.", [{"role": "user", "content": "Say: pong"}], []
    )
    assert response.stop_reason == "end_turn"
    assert any(b.get("type") == "text" and b.get("text") for b in response.content)
