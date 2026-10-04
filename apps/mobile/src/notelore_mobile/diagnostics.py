"""Spike checks (#50): does the shared core work on this device?

Each check runs the real core code and reports instead of raising, so the app
can show every result on screen even when one of them fails.
"""

from __future__ import annotations

import datetime
import importlib
import sqlite3
from collections.abc import Callable
from dataclasses import dataclass

import yaml

from notelore import paths
from notelore.store import format, index, notes


@dataclass(frozen=True)
class Check:
    name: str
    ok: bool
    detail: str


def _round_trip() -> str:
    root = paths.notes_dir()
    path = notes.note_path(root, "topic", "welcome")
    if not path.exists():
        notes.create_note(root, "topic", "Welcome", today=datetime.date.today())
    notes.add_entry(path, "Opened Notelore on this device.")
    note = format.parse(path.read_text(encoding="utf-8"))
    section = note.section("notes")
    entries = [e for e in section.entries if isinstance(e, format.Entry)] if section else []
    return f"{note.title}: {len(entries)} entries"


def _search_index() -> str:
    return "FTS5" if index.fts5_available(sqlite3.connect(":memory:")) else "LIKE fallback"


def _yaml() -> str:
    loaded = yaml.safe_load("title: Şükrü\n")
    return f"parsed {loaded['title']!r}, C loader: {yaml.__with_libyaml__}"


def _importable(*modules: str) -> Callable[[], str]:
    def check() -> str:
        for module in modules:
            importlib.import_module(module)
        return "installed"

    return check


CHECKS: list[tuple[str, Callable[[], str]]] = [
    ("note round trip", _round_trip),
    ("search index", _search_index),
    ("YAML", _yaml),
    ("desktop-only: keyring", _importable("keyring")),
    ("desktop-only: LLM SDKs", _importable("anthropic", "openai")),
]


def run() -> list[Check]:
    results = []
    for name, check in CHECKS:
        try:
            results.append(Check(name, True, check()))
        except ImportError:
            results.append(Check(name, False, "not installed"))
        except Exception as exc:  # the point is to see every failure on the device
            results.append(Check(name, False, f"{type(exc).__name__}: {exc}"))
    return results
