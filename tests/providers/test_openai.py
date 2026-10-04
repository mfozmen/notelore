from __future__ import annotations

from typing import Any

from notelore.providers import Tool
from notelore.providers.openai import API, OpenAIProvider, from_openai, to_openai

from .conftest import Api
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
    *, content: str | None = None, tool_calls: list[Any] | None = None, finish: str | None = "stop"
) -> dict[str, Any]:
    message: dict[str, Any] = {"role": "assistant", "content": content}
    if tool_calls is not None:
        message["tool_calls"] = tool_calls
    return {"choices": [{"message": message, "finish_reason": finish}]}


def test_from_openai_variants() -> None:
    assert from_openai({"choices": []}).content == []
    text = from_openai(completion(content="hello"))
    assert (text.content, text.stop_reason) == ([{"type": "text", "text": "hello"}], "end_turn")
    call = {
        "id": "c1",
        "type": "function",
        "function": {"name": "read_note", "arguments": '{"slug": "x"}'},
    }
    tool = from_openai(completion(tool_calls=[call], finish="tool_calls"))
    assert tool.stop_reason == "tool_use"
    assert tool.content == [
        {"type": "tool_use", "id": "c1", "name": "read_note", "input": {"slug": "x"}}
    ]
    cut = from_openai(completion(content="partial", finish="length"))
    assert cut.content[1]["text"] == "[The model stopped early: length.]"
    assert from_openai(completion(content="x", finish=None)).content == [
        {"type": "text", "text": "x"}
    ]


def test_turn_posts_chat_completions(api: Api) -> None:
    api.answers += [completion(content="ok"), completion(content="ok")]
    provider = OpenAIProvider("sk", "gpt-x")
    assert provider.turn("be brief", [{"role": "user", "content": "hi"}], [TOOL]).content == [
        {"type": "text", "text": "ok"}
    ]
    call = api.last
    assert (call["method"], call["url"]) == ("POST", API)
    assert call["headers"] == {"Authorization": "Bearer sk"}
    assert call["body"]["model"] == "gpt-x"
    assert call["body"]["messages"][0] == {"role": "system", "content": "be brief"}
    assert call["body"]["tools"][0] == {
        "type": "function",
        "function": {
            "name": "read_note",
            "description": "Read a note",
            "parameters": TOOL.input_schema,
        },
    }
    provider.turn("", [{"role": "user", "content": "hi"}], [])
    assert "tools" not in api.last["body"]
    assert api.last["body"]["messages"] == [{"role": "user", "content": "hi"}]  # no empty system
