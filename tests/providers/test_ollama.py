from __future__ import annotations

from typing import Any

import pytest

from notelore.providers import Tool
from notelore.providers.ollama import OllamaProvider, from_ollama, host, to_ollama

from .conftest import Recorder, client_factory, ns
from .test_base import CONVERSATION

TOOL = Tool("read_note", "Read a note", {"type": "object", "properties": {}})


def test_host_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("OLLAMA_HOST", raising=False)
    assert host() == "http://localhost:11434"
    monkeypatch.setenv("OLLAMA_HOST", "http://box:1")
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
    assert from_ollama(ns(message=None)).content == []
    text = from_ollama(ns(message=ns(content="hello", tool_calls=None)))
    assert (text.content, text.stop_reason) == ([{"type": "text", "text": "hello"}], "end_turn")
    call = ns(function=ns(name="read_note", arguments='{"slug": "x"}'))
    tool = from_ollama(ns(message=ns(content="", tool_calls=[call])))
    assert tool.stop_reason == "tool_use"
    assert tool.content[0]["name"] == "read_note"
    assert tool.content[0]["input"] == {"slug": "x"}
    assert tool.content[0]["id"].startswith("toolu_")


def test_turn_forwards_system_tools_and_host(
    fake_module: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("OLLAMA_HOST", "http://box:1")
    recorder = Recorder(ns(message=ns(content="ok", tool_calls=None)))
    fake_module("ollama", Client=client_factory(recorder, "chat"))
    provider = OllamaProvider("llama-x")
    assert provider.turn("be brief", [{"role": "user", "content": "hi"}], [TOOL]).content == [
        {"type": "text", "text": "ok"}
    ]
    call = recorder.calls[0]
    assert call["messages"][0] == {"role": "system", "content": "be brief"}
    assert call["tools"][0]["function"]["name"] == "read_note"
    assert recorder.client_kwargs == {"host": "http://box:1", "timeout": 180.0}
    provider.turn("", [], [])
    assert "tools" not in recorder.calls[1]
