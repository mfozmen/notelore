"""Verify a freshly entered API key with the cheapest possible ping.

Two outcomes the REPL handles differently:

- ``KeyValidationError``: the provider rejected the key. Re-prompt, and forget a
  saved key.
- ``TransientValidationError``: the call failed for another reason (billing,
  rate limit, 5xx, network, daemon down). Keep a saved key; silently wiping it
  over a flaky network would be hostile.
"""

from __future__ import annotations

from notelore.providers.base import ProviderSpec
from notelore.providers.ollama import host

TIMEOUT_SECONDS = 5.0  # a key with working DNS and TLS answers well under a second


class KeyValidationError(Exception):
    """The provider explicitly rejected the key."""


class TransientValidationError(Exception):
    """The ping failed, but the key is not the reason."""


def validate_key(spec: ProviderSpec, api_key: str) -> None:
    _CHECKERS[spec.name](spec, api_key)


def _check_anthropic(spec: ProviderSpec, api_key: str) -> None:
    import anthropic

    try:
        anthropic.Anthropic(api_key=api_key, timeout=TIMEOUT_SECONDS).messages.create(
            model=spec.validation_model,
            max_tokens=1,
            messages=[{"role": "user", "content": "ping"}],
        )
    except (anthropic.AuthenticationError, anthropic.PermissionDeniedError) as exc:
        raise KeyValidationError(f"Anthropic rejected the key: {exc}") from exc
    except anthropic.APIError as exc:
        raise TransientValidationError(f"Anthropic call failed: {exc}") from exc


def _check_openai(spec: ProviderSpec, api_key: str) -> None:
    import openai

    try:
        openai.OpenAI(api_key=api_key, timeout=TIMEOUT_SECONDS).chat.completions.create(
            model=spec.validation_model,
            max_tokens=1,
            messages=[{"role": "user", "content": "ping"}],
        )
    except (openai.AuthenticationError, openai.PermissionDeniedError) as exc:
        raise KeyValidationError(f"OpenAI rejected the key: {exc}") from exc
    except openai.APIError as exc:
        raise TransientValidationError(f"OpenAI call failed: {exc}") from exc


def _check_gemini(spec: ProviderSpec, api_key: str) -> None:
    """Gemini answers a bad key with HTTP 400 "API key not valid", so classify by
    status and message rather than by exception class alone."""
    from google import genai
    from google.genai import errors

    try:
        genai.Client(api_key=api_key).models.generate_content(
            model=spec.validation_model, contents="ping"
        )
    except errors.APIError as exc:
        status = getattr(exc, "code", None)
        message = str(exc).lower()
        if status in (401, 403) or "api key" in message or "unauthenticated" in message:
            raise KeyValidationError(f"Google rejected the key: {exc}") from exc
        raise TransientValidationError(f"Gemini call failed: {exc}") from exc


def _check_ollama(_spec: ProviderSpec, _api_key: str) -> None:
    """Key-less: the ping only asks whether the local daemon answers."""
    import ollama

    try:
        ollama.Client(host=host(), timeout=TIMEOUT_SECONDS).list()
    except Exception as exc:
        raise TransientValidationError(
            f"Ollama is not reachable on {host()}; start the daemon and retry. ({exc})"
        ) from exc


_CHECKERS = {
    "anthropic": _check_anthropic,
    "openai": _check_openai,
    "gemini": _check_gemini,
    "ollama": _check_ollama,
}
