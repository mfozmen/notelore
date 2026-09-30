from __future__ import annotations

import types
from typing import Any

from notelore.providers import Tool
from notelore.providers.gemini import GeminiProvider, from_gemini, to_gemini

from .conftest import Recorder, client_factory, ns
from .test_base import CONVERSATION

TOOL = Tool("read_note", "Read a note", {"type": "object", "properties": {}})


class FakeTypes(types.SimpleNamespace):
    """Stand-in for ``google.genai.types``: every class is a SimpleNamespace factory."""

    def __init__(self) -> None:
        def factory(**kwargs: Any) -> types.SimpleNamespace:
            return ns(**kwargs)

        super().__init__(
            Content=factory,
            Part=_Part,
            FunctionCall=factory,
            FunctionResponse=factory,
            FunctionDeclaration=factory,
            Tool=factory,
            HttpOptions=factory,
            GenerateContentConfig=factory,
        )


class _Part(types.SimpleNamespace):
    @staticmethod
    def from_text(text: str) -> types.SimpleNamespace:
        return ns(text=text)


def test_to_gemini_roles_and_function_parts() -> None:
    contents = to_gemini(CONVERSATION, FakeTypes())
    assert [c.role for c in contents] == ["user", "model", "tool"]
    assert contents[0].parts[0].text == "hi"
    model_parts = contents[1].parts
    assert model_parts[0].text == "checking"
    assert model_parts[1].function_call.name == "read_note"
    assert model_parts[1].function_call.args == {"slug": "x"}
    response = contents[2].parts[0].function_response
    assert (response.id, response.name, response.response) == ("t1", "read_note", {"result": "ok"})


def candidate(parts: list[Any], finish: str = "STOP") -> Any:
    return ns(candidates=[ns(content=ns(parts=parts), finish_reason=finish)])


def test_from_gemini_variants() -> None:
    assert from_gemini(ns(candidates=[])).content == []
    text = from_gemini(candidate([ns(text="hello", function_call=None)]))
    assert (text.content, text.stop_reason) == ([{"type": "text", "text": "hello"}], "end_turn")
    with_id = ns(text=None, function_call=ns(id="g1", name="read_note", args={"slug": "x"}))
    without_id = ns(text=None, function_call=ns(id=None, name="search_notes", args=None))
    tool = from_gemini(candidate([with_id, without_id]))
    assert tool.stop_reason == "tool_use"
    assert tool.content[0] == {
        "type": "tool_use",
        "id": "g1",
        "name": "read_note",
        "input": {"slug": "x"},
    }
    assert tool.content[1]["id"].startswith("toolu_")
    assert tool.content[1]["input"] == {}
    blocked = from_gemini(candidate([ns(text=None, function_call=None)], finish="SAFETY"))
    assert blocked.content == [{"type": "text", "text": "[The model stopped early: SAFETY.]"}]


def test_turn_builds_client_config_and_tools(fake_module: Any) -> None:
    recorder = Recorder(candidate([ns(text="ok", function_call=None)]))
    fake_types = FakeTypes()
    fake_module("google")
    fake_module(
        "google.genai", Client=client_factory(recorder, "models.generate_content"), types=fake_types
    )
    fake_module("google.genai.types", **vars(fake_types))
    provider = GeminiProvider("gk", "gemini-x")
    response = provider.turn("be brief", [{"role": "user", "content": "hi"}], [TOOL])
    assert response.content == [{"type": "text", "text": "ok"}]
    call = recorder.calls[0]
    assert call["model"] == "gemini-x"
    assert call["contents"][0].parts[0].text == "hi"
    assert call["config"].system_instruction == "be brief"
    assert call["config"].tools[0].function_declarations[0].name == "read_note"
    assert recorder.client_kwargs["api_key"] == "gk"
    assert recorder.client_kwargs["http_options"].timeout == 60_000
    provider.turn("", [], [])
    assert not hasattr(recorder.calls[1]["config"], "tools")
