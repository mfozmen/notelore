from __future__ import annotations

from notelore.providers import Tool
from notelore.providers.anthropic import API, AnthropicProvider, block_to_dict

from .conftest import Api

TOOL = Tool("read_note", "Read a note", {"type": "object", "properties": {}})


def test_turn_posts_the_messages_api(api: Api) -> None:
    api.answers.append(
        {"content": [{"type": "text", "text": "hi", "citations": None}], "stop_reason": "end_turn"}
    )
    response = AnthropicProvider("sk-ant", "claude-x").turn(
        "be brief", [{"role": "user", "content": "hello"}], [TOOL]
    )
    assert response.stop_reason == "end_turn"
    assert response.content == [{"type": "text", "text": "hi"}]  # response-only fields dropped
    call = api.last
    assert (call["method"], call["url"]) == ("POST", API)
    assert call["headers"] == {"x-api-key": "sk-ant", "anthropic-version": "2023-06-01"}
    assert call["body"] == {
        "model": "claude-x",
        "max_tokens": 4096,
        "system": "be brief",
        "messages": [{"role": "user", "content": "hello"}],
        "tools": [
            {"name": "read_note", "description": "Read a note", "input_schema": TOOL.input_schema}
        ],
    }
    assert 0 < call["timeout"] <= 300


def test_tool_use_and_no_tools_or_system(api: Api) -> None:
    api.answers.append(
        {
            "content": [
                {"type": "tool_use", "id": "t1", "name": "read_note", "input": {"slug": "x"}}
            ],
            "stop_reason": "tool_use",
        }
    )
    response = AnthropicProvider("sk", "m").turn("", [], [])
    assert "tools" not in api.last["body"]
    assert "system" not in api.last["body"]
    assert response.stop_reason == "tool_use"
    assert response.content == [
        {"type": "tool_use", "id": "t1", "name": "read_note", "input": {"slug": "x"}}
    ]


def test_max_tokens_cutoff_is_reported(api: Api) -> None:
    api.answers.append(
        {"content": [{"type": "text", "text": "partial"}], "stop_reason": "max_tokens"}
    )
    response = AnthropicProvider("sk", "m").turn("", [], [])
    assert response.stop_reason == "end_turn"
    assert response.content[1] == {"type": "text", "text": "[The model stopped early: max_tokens.]"}


def test_block_to_dict_whitelists_fields() -> None:
    assert block_to_dict({"type": "text", "text": "hi", "extra": 1}) == {
        "type": "text",
        "text": "hi",
    }
    assert block_to_dict({"type": "thinking", "thinking": "..."}) == {"type": "thinking"}
