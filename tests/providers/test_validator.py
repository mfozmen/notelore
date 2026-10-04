from __future__ import annotations

import urllib.error

import pytest

from notelore.providers import find
from notelore.providers.http import HTTPError
from notelore.providers.validator import (
    KeyValidationError,
    TransientValidationError,
    validate_key,
)

from .conftest import Api


@pytest.mark.parametrize(
    ("provider", "url", "headers"),
    [
        (
            "anthropic",
            "https://api.anthropic.com/v1/models",
            {"x-api-key": "key", "anthropic-version": "2023-06-01"},
        ),
        ("openai", "https://api.openai.com/v1/models", {"Authorization": "Bearer key"}),
        (
            "gemini",
            "https://generativelanguage.googleapis.com/v1beta/models",
            {"x-goog-api-key": "key"},
        ),
    ],
)
def test_a_good_key_lists_the_models_and_spends_no_tokens(
    api: Api, provider: str, url: str, headers: dict[str, str]
) -> None:
    api.answers.append({"data": []})
    validate_key(find(provider), "key")
    assert api.last == {
        "method": "GET",
        "url": url,
        "headers": headers,
        "body": None,
        "timeout": 5.0,
    }


@pytest.mark.parametrize("provider", ["anthropic", "openai", "gemini"])
@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (HTTPError(401, "invalid x-api-key"), KeyValidationError),
        (HTTPError(403, "permission denied"), KeyValidationError),
        (HTTPError(429, "rate limited"), TransientValidationError),
        (HTTPError(500, "overloaded"), TransientValidationError),
        (urllib.error.URLError("no route to host"), TransientValidationError),
    ],
)
def test_rejected_keys_and_transient_failures(
    api: Api, provider: str, error: Exception, expected: type[Exception]
) -> None:
    api.answers.append(error)
    with pytest.raises(expected):
        validate_key(find(provider), "key")


def test_gemini_reports_a_bad_key_as_400(api: Api) -> None:
    api.answers.append(HTTPError(400, "API key not valid. Please pass a valid API key."))
    with pytest.raises(KeyValidationError, match="Google rejected the key"):
        validate_key(find("gemini"), "key")
    api.answers.append(HTTPError(400, "Invalid JSON payload"))
    with pytest.raises(TransientValidationError):
        validate_key(find("gemini"), "key")


def test_ollama_only_needs_a_reachable_daemon(api: Api, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OLLAMA_HOST", "http://box:1")
    api.answers.append({"models": []})
    validate_key(find("ollama"), "")
    assert api.last["url"] == "http://box:1/api/tags"
    api.answers.append(urllib.error.URLError("connection refused"))
    with pytest.raises(TransientValidationError, match="http://box:1"):
        validate_key(find("ollama"), "")
