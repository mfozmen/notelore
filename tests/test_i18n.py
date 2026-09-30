from __future__ import annotations

from notelore.i18n import section_heading, section_key


def test_section_key_accepts_every_known_heading_variant() -> None:
    assert section_key("Decisions") == section_key("Kararlar") == "decisions"
    assert section_key("Notes") == section_key("Notlar") == "notes"
    assert section_key("Todo") == section_key("Yapılacaklar") == "todo"
    assert section_key("Links") is None


def test_section_heading_falls_back_to_english() -> None:
    assert section_heading("todo") == "Todo"
    assert section_heading("todo", "tr") == "Yapılacaklar"
    assert section_heading("todo", "de") == "Todo"
