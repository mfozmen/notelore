from __future__ import annotations

import pytest

from notelore.providers import SPECS, Message, Tool, create_provider, find
from notelore.providers.anthropic import AnthropicProvider
from notelore.providers.base import parse_arguments, split_blocks, tool_use_names
from notelore.providers.gemini import GeminiProvider
from notelore.providers.ollama import OllamaProvider
from notelore.providers.openai import OpenAIProvider

CONVERSATION: list[Message] = [
    {"role": "user", "content": "hi"},
    {
        "role": "assistant",
        "content": [
            {"type": "text", "text": "checking"},
            {"type": "tool_use", "id": "t1", "name": "read_note", "input": {"slug": "x"}},
            {"type": "tool_use", "name": "no-id-is-skipped", "input": {}},
        ],
    },
    {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]},
]


def test_find_known_and_unknown() -> None:
    assert find("anthropic").display_name == "Claude (Anthropic)"
    assert [s.name for s in SPECS] == ["anthropic", "openai", "gemini", "ollama"]
    with pytest.raises(KeyError, match="unknown provider"):
        find("bard")


@pytest.mark.parametrize(
    ("name", "cls"),
    [
        ("anthropic", AnthropicProvider),
        ("openai", OpenAIProvider),
        ("gemini", GeminiProvider),
        ("ollama", OllamaProvider),
    ],
)
def test_create_provider(name: str, cls: type) -> None:
    provider = create_provider(find(name), "key")
    assert isinstance(provider, cls)
    assert provider._model == find(name).default_model  # type: ignore[attr-defined]
    custom = create_provider(find(name), None, model="other")
    assert custom._model == "other"  # type: ignore[attr-defined]


def test_tool_use_names_skips_ids_less_blocks() -> None:
    assert tool_use_names(CONVERSATION) == {"t1": "read_note"}


def test_split_blocks() -> None:
    assert split_blocks("plain") == (["plain"], [], [])
    texts, uses, results = split_blocks(CONVERSATION[1]["content"])
    assert texts == ["checking"]
    assert [u["name"] for u in uses] == ["read_note", "no-id-is-skipped"]
    assert results == []
    assert split_blocks(CONVERSATION[2]["content"])[2][0]["tool_use_id"] == "t1"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ({"a": 1}, {"a": 1}),
        ('{"a": 1}', {"a": 1}),
        ("", {}),
        (None, {}),
        ("not json", {"__raw": "not json"}),
        ("[1, 2]", {"__raw": "[1, 2]"}),
    ],
)
def test_parse_arguments(raw: object, expected: dict[str, object]) -> None:
    assert parse_arguments(raw) == expected


def test_tool_is_a_plain_record() -> None:
    tool = Tool("noop", "does nothing", {"type": "object", "properties": {}})
    assert tool.input_schema["type"] == "object"
