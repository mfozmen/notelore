"""API keys and tokens in the OS credential store via ``keyring``.

``NOTELORE_<PROVIDER>_API_KEY`` environment variables override the store for
dev and CI. Every keyring failure (no backend, locked-down container) degrades
to "not saved": the app still works, the user just re-enters the key next time.
"""

from __future__ import annotations

import contextlib
import os

import keyring

SERVICE = "notelore"


def env_var(provider: str) -> str:
    return f"NOTELORE_{provider.upper()}_API_KEY"


def load_key(provider: str) -> str | None:
    if value := os.environ.get(env_var(provider)):
        return value
    try:
        stored = keyring.get_password(SERVICE, provider)
    except Exception:
        return None
    return stored or None


def save_key(provider: str, key: str) -> None:
    with contextlib.suppress(Exception):
        keyring.set_password(SERVICE, provider, key)


def delete_key(provider: str) -> None:
    with contextlib.suppress(Exception):  # nothing saved, or no backend: both fine for /logout
        keyring.delete_password(SERVICE, provider)
