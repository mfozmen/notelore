from __future__ import annotations

from typing import Any

from notelore.providers import Tool
from notelore.providers.anthropic import AnthropicProvider, block_to_dict

from .conftest import Recorder, client_factory, ns

TOOL = Tool("read_note", "Read a note", {"type": "object", "properties": {}})


class Dumpable:
    def __init__(self, **data: Any) -> None:
        self.data = data

    def model_dump(self) -> dict[str, Any]:
        return dict(self.data)


def test_turn_forwards_system_messages_and_tools(fake_module: Any) -> None:
    recorder = Recorder(ns(content=[Dumpable(type="text", text="hi")], stop_reason="end_turn"))
    fake_module("anthropic", Anthropic=client_factory(recorder, "messages.create"))
    response = AnthropicProvider("sk", "claude-x").turn(
        "be brief", [{"role": "user", "content": "hello"}], [TOOL]
    )
    assert response.stop_reason == "end_turn"
    assert response.content == [{"type": "text", "text": "hi"}]
    call = recorder.calls[0]
    assert call["model"] == "claude-x"
    assert call["system"] == "be brief"
    assert call["messages"] == [{"role": "user", "content": "hello"}]
    assert call["tools"] == [
        {"name": "read_note", "description": "Read a note", "input_schema": TOOL.input_schema}
    ]
    assert recorder.client_kwargs["api_key"] == "sk"
    assert 0 < recorder.client_kwargs["timeout"] <= 300


def test_turn_without_tools_and_with_tool_use(fake_module: Any) -> None:
    blocks = [Dumpable(type="tool_use", id="t1", name="read_note", input={"slug": "x"})]
    recorder = Recorder(ns(content=blocks, stop_reason="tool_use"))
    fake_module("anthropic", Anthropic=client_factory(recorder, "messages.create"))
    response = AnthropicProvider("sk", "m").turn("", [], [])
    assert "tools" not in recorder.calls[0]
    assert response.stop_reason == "tool_use"
    assert response.content[0]["name"] == "read_note"


def test_block_to_dict_without_model_dump() -> None:
    assert block_to_dict(ns(type="text", text="hi")) == {"type": "text", "text": "hi"}
    assert block_to_dict(ns(type="tool_use", id="t", name="n", input={"k": 1})) == {
        "type": "tool_use",
        "id": "t",
        "name": "n",
        "input": {"k": 1},
    }
    assert block_to_dict(ns(type="thinking")) == {"type": "thinking"}
