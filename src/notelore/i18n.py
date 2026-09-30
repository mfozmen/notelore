"""Structural strings in English and Turkish. English is the fallback.

Note *content* is written in whatever language the user speaks; only the
structure (section headings, prompts) is translated here.
"""

from __future__ import annotations

SECTION_HEADINGS: dict[str, dict[str, str]] = {
    "decisions": {"en": "Decisions", "tr": "Kararlar"},
    "notes": {"en": "Notes", "tr": "Notlar"},
    "todo": {"en": "Todo", "tr": "Yapılacaklar"},
}

_HEADING_TO_KEY: dict[str, str] = {
    heading: key for key, variants in SECTION_HEADINGS.items() for heading in variants.values()
}


def section_key(heading: str) -> str | None:
    """Canonical key for a known section heading in any language, else None."""
    return _HEADING_TO_KEY.get(heading)


def section_heading(key: str, lang: str = "en") -> str:
    variants = SECTION_HEADINGS[key]
    return variants.get(lang, variants["en"])
