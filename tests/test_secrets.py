from __future__ import annotations

import pytest

from notelore import secrets


class FakeKeyring:
    def __init__(self, broken: bool = False) -> None:
        self.store: dict[tuple[str, str], str] = {}
        self.broken = broken

    def get_password(self, service: str, user: str) -> str | None:
        if self.broken:
            raise RuntimeError("no backend")
        return self.store.get((service, user))

    def set_password(self, service: str, user: str, value: str) -> None:
        if self.broken:
            raise RuntimeError("no backend")
        self.store[(service, user)] = value

    def delete_password(self, service: str, user: str) -> None:
        if self.broken or (service, user) not in self.store:
            raise RuntimeError("nothing to delete")
        del self.store[(service, user)]


@pytest.fixture
def ring(monkeypatch: pytest.MonkeyPatch) -> FakeKeyring:
    fake = FakeKeyring()
    for name in ("get_password", "set_password", "delete_password"):
        monkeypatch.setattr(f"keyring.{name}", getattr(fake, name))
    monkeypatch.delenv("NOTELORE_ANTHROPIC_API_KEY", raising=False)
    return fake


def test_round_trip_through_the_keyring(ring: FakeKeyring) -> None:
    assert secrets.load_key("anthropic") is None
    secrets.save_key("anthropic", "sk-1")
    assert ring.store == {("notelore", "anthropic"): "sk-1"}
    assert secrets.load_key("anthropic") == "sk-1"
    secrets.delete_key("anthropic")
    secrets.delete_key("anthropic")  # nothing saved any more: still fine
    assert secrets.load_key("anthropic") is None


def test_env_var_overrides_the_keyring(ring: FakeKeyring, monkeypatch: pytest.MonkeyPatch) -> None:
    secrets.save_key("anthropic", "sk-stored")
    monkeypatch.setenv("NOTELORE_ANTHROPIC_API_KEY", "sk-env")
    assert secrets.load_key("anthropic") == "sk-env"
    assert secrets.env_var("gemini") == "NOTELORE_GEMINI_API_KEY"


def test_a_missing_backend_degrades_to_not_saved(ring: FakeKeyring) -> None:
    ring.broken = True
    secrets.save_key("openai", "sk")
    assert secrets.load_key("openai") is None
    secrets.delete_key("openai")
