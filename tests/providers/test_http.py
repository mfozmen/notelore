from __future__ import annotations

import io
import json
import ssl
import urllib.error
from typing import Any

import pytest

from notelore.providers import http


class Response(io.BytesIO):
    def __enter__(self) -> Response:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


@pytest.fixture
def opened(monkeypatch: pytest.MonkeyPatch) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []

    def urlopen(request: Any, timeout: float, context: ssl.SSLContext) -> Response:
        calls.append({"request": request, "timeout": timeout, "context": context})
        if "fail" in request.full_url:
            code = int(request.full_url.rsplit("/", 1)[1])
            body = request.full_url.split("fail-", 1)[1].split("/", 1)[0].encode()
            raise urllib.error.HTTPError(request.full_url, code, "error", {}, io.BytesIO(body))  # type: ignore[arg-type]
        return Response(b'{"ok": true}' if "empty" not in request.full_url else b"")

    monkeypatch.setattr("urllib.request.urlopen", urlopen)
    return calls


def test_post_sends_json_with_headers_and_returns_json(opened: list[dict[str, Any]]) -> None:
    assert http.request("POST", "https://api.x/v1", {"x-api-key": "k"}, {"a": "ş"}, 7.0) == {
        "ok": True
    }
    request = opened[0]["request"]
    assert request.get_method() == "POST"
    assert json.loads(request.data) == {"a": "ş"}
    assert request.get_header("X-api-key") == "k"
    assert request.get_header("Content-type") == "application/json"
    assert opened[0]["timeout"] == 7.0
    assert isinstance(opened[0]["context"], ssl.SSLContext)


def test_get_without_body_and_an_empty_answer(opened: list[dict[str, Any]]) -> None:
    assert http.request("GET", "https://api.x/empty") is None
    assert opened[0]["request"].data is None
    assert opened[0]["request"].get_method() == "GET"


@pytest.mark.parametrize(
    ("body", "message"),
    [
        (
            '{"error": {"message": "invalid x-api-key"}}',
            "invalid x-api-key",
        ),  # Anthropic, OpenAI, Gemini
        ('{"error": "model not found"}', "model not found"),  # Ollama
        ("upstream timed out", "upstream timed out"),
    ],
    ids=["nested", "flat", "not-json"],
)
def test_http_errors_carry_status_and_the_api_message(
    opened: list[dict[str, Any]], body: str, message: str
) -> None:
    with pytest.raises(http.HTTPError) as caught:
        http.request("GET", f"https://api.x/fail-{body}/401")
    assert caught.value.status == 401
    assert caught.value.message == message
    assert str(caught.value) == f"HTTP 401: {message}"


def test_the_tls_context_uses_the_bundled_ca_certificates() -> None:
    context = http.tls_context()
    assert context.verify_mode == ssl.CERT_REQUIRED
    assert context.check_hostname
    assert len(context.get_ca_certs()) > 50  # certifi's bundle, not an empty platform store
    assert http.tls_context() is context
