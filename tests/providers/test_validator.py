from __future__ import annotations

from typing import Any

import pytest

from notelore.providers import find
from notelore.providers.validator import (
    KeyValidationError,
    TransientValidationError,
    validate_key,
)

from .conftest import Recorder, client_factory, ns


class Auth(Exception):
    pass


class Denied(Exception):
    pass


class Api(Exception):
    def __init__(self, message: str, code: int | None = None) -> None:
        super().__init__(message)
        self.code = code


def install(fake_module: Any, name: str, client_attr: str, method: str, recorder: Recorder) -> None:
    fake_module(
        name,
        AuthenticationError=Auth,
        PermissionDeniedError=Denied,
        APIError=Api,
        **{client_attr: client_factory(recorder, method)},
    )


@pytest.mark.parametrize(
    ("provider", "module", "client_attr", "method"),
    [
        ("anthropic", "anthropic", "Anthropic", "messages.create"),
        ("openai", "openai", "OpenAI", "chat.completions.create"),
    ],
)
@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (None, None),
        (Auth("bad key"), KeyValidationError),
        (Denied("no"), KeyValidationError),
        (Api("500"), TransientValidationError),
    ],
)
def test_anthropic_and_openai_checkers(
    fake_module: Any,
    provider: str,
    module: str,
    client_attr: str,
    method: str,
    error: Exception | None,
    expected: type | None,
) -> None:
    recorder = Recorder(error if error else ns())
    install(fake_module, module, client_attr, method, recorder)
    if expected is None:
        validate_key(find(provider), "key")
    else:
        with pytest.raises(expected):
            validate_key(find(provider), "key")
    assert recorder.calls[0]["max_tokens"] == 1
    assert recorder.calls[0]["model"] == find(provider).validation_model
    assert recorder.client_kwargs == {"api_key": "key", "timeout": 5.0}


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (None, None),
        (Api("API key not valid", 400), KeyValidationError),
        (Api("forbidden", 403), KeyValidationError),
        (Api("unauthenticated", None), KeyValidationError),
        (Api("quota exceeded", 429), TransientValidationError),
    ],
)
def test_gemini_checker(fake_module: Any, error: Exception | None, expected: type | None) -> None:
    recorder = Recorder(error if error else ns())
    fake_module("google")
    fake_module(
        "google.genai",
        Client=client_factory(recorder, "models.generate_content"),
        errors=ns(APIError=Api),
    )
    fake_module("google.genai.errors", APIError=Api)
    if expected is None:
        validate_key(find("gemini"), "key")
    else:
        with pytest.raises(expected):
            validate_key(find("gemini"), "key")
    assert recorder.calls[0] == {"model": "gemini-2.5-flash", "contents": "ping"}


def test_ollama_checker(fake_module: Any, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OLLAMA_HOST", "http://box:1")
    recorder = Recorder(ns())
    fake_module("ollama", Client=client_factory(recorder, "list"))
    validate_key(find("ollama"), "")
    assert recorder.client_kwargs == {"host": "http://box:1", "timeout": 5.0}
    fake_module("ollama", Client=client_factory(Recorder(ConnectionError("down")), "list"))
    with pytest.raises(TransientValidationError, match="http://box:1"):
        validate_key(find("ollama"), "")
