"""JSON over HTTPS for the providers: the standard library plus certifi's CA bundle.

No vendor SDKs, so the same code runs on the desktop, Android and iOS: the SDKs
pull pydantic-core and jiter, which have no mobile wheels (#51). certifi's
bundle is used everywhere because mobile Python builds and some desktop ones
(python.org on macOS) have no usable system CA store.
"""

from __future__ import annotations

import functools
import json
import ssl
import urllib.error
import urllib.request
from typing import Any

import certifi


class HTTPError(Exception):
    """The API answered with an error status; ``message`` is the API's own text."""

    def __init__(self, status: int, message: str) -> None:
        super().__init__(f"HTTP {status}: {message}")
        self.status = status
        self.message = message


@functools.cache
def tls_context() -> ssl.SSLContext:
    return ssl.create_default_context(cafile=certifi.where())


def request(
    method: str,
    url: str,
    headers: dict[str, str] | None = None,
    body: Any = None,
    timeout: float = 60.0,
) -> Any:
    """Send ``body`` as JSON, return the decoded JSON answer (None for an empty one).

    Raises HTTPError for an error status and OSError (URLError) when the server
    cannot be reached.
    """
    data = json.dumps(body).encode("utf-8") if body is not None else None
    prepared = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    try:
        with urllib.request.urlopen(prepared, timeout=timeout, context=tls_context()) as answer:
            raw = answer.read()
    except urllib.error.HTTPError as exc:
        raise HTTPError(exc.code, _message(exc.read())) from exc
    return json.loads(raw) if raw else None


def _message(raw: bytes) -> str:
    """The error text from {"error": {"message": ...}} or {"error": "..."}, else the raw body."""
    text = raw.decode("utf-8", "replace")
    try:
        error = json.loads(text)["error"]
    except (ValueError, KeyError, TypeError):
        return text
    return str(error["message"]) if isinstance(error, dict) and "message" in error else str(error)
