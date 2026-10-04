from __future__ import annotations

import pytest

from notelore.providers import Tool
from notelore.providers.ollama import OllamaProvider, from_ollama, host, to_ollama

from .conftest import Api
from .test_base import CONVERSATION

TOOL = Tool("read_note", "Read a note", {"type": "object", "properties": {}})


def test_host_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("OLLAMA_HOST", raising=False)
    assert host() == "http://localhost:11434"
    monkeypatch.setenv("OLLAMA_HOST", "http://box:1/")
    assert host() == "http://box:1"


def test_to_ollama_translates_by_tool_name() -> None:
    assert to_ollama(CONVERSATION) == [
        {"role": "user", "content": "hi"},
        {
            "role": "assistant",
            "content": "checking",
            "tool_calls": [
                {"function": {"name": "read_note", "arguments": {"slug": "x"}}},
                {"function": {"name": "no-id-is-skipped", "arguments": {}}},
            ],
        },
        {"role": "tool", "content": "ok", "tool_name": "read_note"},
    ]
    assert to_ollama([{"role": "assistant", "content": []}]) == [
        {"role": "assistant", "content": ""}
    ]


def test_from_ollama_variants() -> None:
    assert from_ollama({}).content == []
    text = from_ollama({"message": {"content": "hello"}})
    assert (text.content, text.stop_reason) == ([{"type": "text", "text": "hello"}], "end_turn")
    calls = [
        {"function": {"name": "read_note", "arguments": {"slug": "x"}}},
        {"function": {"name": "search_notes", "arguments": '{"query": "q"}'}},  # some models
    ]
    tool = from_ollama({"message": {"content": "", "tool_calls": calls}})
    assert tool.stop_reason == "tool_use"
    assert [b["input"] for b in tool.content] == [{"slug": "x"}, {"query": "q"}]
    assert all(b["id"].startswith("toolu_") for b in tool.content)


def test_turn_posts_api_chat_without_streaming(api: Api, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OLLAMA_HOST", "http://box:1")
    api.answers += [{"message": {"content": "ok"}}, {"message": {"content": "ok"}}]
    provider = OllamaProvider("llama-x")
    assert provider.turn("be brief", [{"role": "user", "content": "hi"}], [TOOL]).content == [
        {"type": "text", "text": "ok"}
    ]
    call = api.last
    assert (call["method"], call["url"]) == ("POST", "http://box:1/api/chat")
    assert call["body"]["stream"] is False
    assert call["body"]["model"] == "llama-x"
    assert call["body"]["messages"][0] == {"role": "system", "content": "be brief"}
    assert call["body"]["tools"][0]["function"]["name"] == "read_note"
    assert call["timeout"] == 180.0
    provider.turn("", [{"role": "user", "content": "hi"}], [])
    assert "tools" not in api.last["body"]
    assert api.last["body"]["messages"] == [{"role": "user", "content": "hi"}]
