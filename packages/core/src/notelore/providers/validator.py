"""Verify a freshly entered API key by listing the provider's models.

Listing models is free (no tokens) and needs a valid key. Two outcomes the REPL
handles differently:

- ``KeyValidationError``: the provider rejected the key. Re-prompt, and forget a
  saved key.
- ``TransientValidationError``: the call failed for another reason (rate limit,
  5xx, network, daemon down). Keep a saved key; silently wiping it over a flaky
  network would be hostile.
"""

from __future__ import annotations

from notelore.providers import anthropic, gemini, http, ollama, openai
from notelore.providers.base import ProviderSpec

TIMEOUT_SECONDS = 5.0  # a key with working DNS and TLS answers well under a second

_REQUESTS = {
    "anthropic": (anthropic.MODELS, anthropic.headers, "Anthropic"),
    "openai": (openai.MODELS, openai.headers, "OpenAI"),
    "gemini": (gemini.BASE, gemini.headers, "Google"),
}


class KeyValidationError(Exception):
    """The provider explicitly rejected the key."""


class TransientValidationError(Exception):
    """The check failed, but the key is not the reason."""


def validate_key(spec: ProviderSpec, api_key: str) -> None:
    if spec.name == "ollama":
        _check_ollama()
        return
    url, make_headers, vendor = _REQUESTS[spec.name]
    try:
        http.request("GET", url, make_headers(api_key), None, TIMEOUT_SECONDS)
    except http.HTTPError as exc:
        # Gemini answers a bad key with 400 "API key not valid" rather than 401/403.
        if exc.status in (401, 403) or (exc.status == 400 and "api key" in exc.message.lower()):
            raise KeyValidationError(f"{vendor} rejected the key: {exc.message}") from exc
        raise TransientValidationError(f"{vendor} call failed: {exc}") from exc
    except OSError as exc:
        raise TransientValidationError(f"{vendor} is not reachable: {exc}") from exc


def _check_ollama() -> None:
    """Key-less: the check only asks whether the local daemon answers."""
    try:
        http.request("GET", f"{ollama.host()}/api/tags", None, None, TIMEOUT_SECONDS)
    except (http.HTTPError, OSError) as exc:
        raise TransientValidationError(
            f"Ollama is not reachable on {ollama.host()}; start the daemon and retry. ({exc})"
        ) from exc
