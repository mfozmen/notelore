from __future__ import annotations

from typing import Any

from notelore.providers import Tool
from notelore.providers.openai import OpenAIProvider, from_openai, to_openai

from .conftest import Recorder, client_factory, ns
from .test_base import CONVERSATION

TOOL = Tool("read_note", "Read a note", {"type": "object", "properties": {}})


def test_to_openai_translates_tool_calls_and_results() -> None:
    assert to_openai(CONVERSATION) == [
        {"role": "user", "content": "hi"},
        {
            "role": "assistant",
            "content": "checking",
            "tool_calls": [
                {
                    "id": "t1",
                    "type": "function",
                    "function": {"name": "read_note", "arguments": '{"slug": "x"}'},
                },
                {
                    "id": "",
                    "type": "function",
                    "function": {"name": "no-id-is-skipped", "arguments": "{}"},
                },
            ],
        },
        {"role": "tool", "tool_call_id": "t1", "content": "ok"},
    ]
    assert to_openai([{"role": "assistant", "content": []}]) == [
        {"role": "assistant", "content": None}
    ]


def completion(
    *, content: str | None = None, tool_calls: list[Any] | None = None, finish: str = "stop"
) -> Any:
    return ns(
        choices=[ns(message=ns(content=content, tool_calls=tool_calls), finish_reason=finish)]
    )


def test_from_openai_variants() -> None:
    assert from_openai(ns(choices=[])).content == []
    text = from_openai(completion(content="hello"))
    assert (text.content, text.stop_reason) == ([{"type": "text", "text": "hello"}], "end_turn")
    call = ns(id="c1", function=ns(name="read_note", arguments='{"slug": "x"}'))
    tool = from_openai(completion(tool_calls=[call], finish="tool_calls"))
    assert tool.stop_reason == "tool_use"
    assert tool.content == [
        {"type": "tool_use", "id": "c1", "name": "read_note", "input": {"slug": "x"}}
    ]
    cut = from_openai(completion(content="partial", finish="length"))
    assert cut.content[1]["text"] == "[The model stopped early: length.]"


def test_turn_forwards_system_as_first_message_and_tools(fake_module: Any) -> None:
    recorder = Recorder(completion(content="ok"))
    fake_module("openai", OpenAI=client_factory(recorder, "chat.completions.create"))
    provider = OpenAIProvider("sk", "gpt-x")
    assert provider.turn("be brief", [{"role": "user", "content": "hi"}], [TOOL]).content == [
        {"type": "text", "text": "ok"}
    ]
    call = recorder.calls[0]
    assert call["messages"][0] == {"role": "system", "content": "be brief"}
    assert call["tools"][0]["function"]["name"] == "read_note"
    assert recorder.client_kwargs == {"api_key": "sk", "timeout": 60.0}
    provider.turn("", [], [])
    assert "tools" not in recorder.calls[1]
