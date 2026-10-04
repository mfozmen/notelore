from __future__ import annotations

from typing import Any

from notelore.providers import Tool
from notelore.providers.gemini import GeminiProvider, endpoint, from_gemini, to_gemini

from .conftest import Api
from .test_base import CONVERSATION

TOOL = Tool("read_note", "Read a note", {"type": "object", "properties": {}})


def test_to_gemini_roles_and_function_parts() -> None:
    assert to_gemini(CONVERSATION) == [
        {"role": "user", "parts": [{"text": "hi"}]},
        {
            "role": "model",
            "parts": [
                {"text": "checking"},
                {"functionCall": {"name": "read_note", "args": {"slug": "x"}}},
                {"functionCall": {"name": "no-id-is-skipped", "args": {}}},
            ],
        },
        # Gemini expects function responses under role "user"
        {
            "role": "user",
            "parts": [{"functionResponse": {"name": "read_note", "response": {"result": "ok"}}}],
        },
    ]


def candidate(parts: list[dict[str, Any]], finish: str = "STOP") -> dict[str, Any]:
    return {"candidates": [{"content": {"role": "model", "parts": parts}, "finishReason": finish}]}


def test_from_gemini_variants() -> None:
    assert from_gemini({}).content == []
    assert from_gemini({"candidates": [{"finishReason": "SAFETY"}]}).content == [
        {"type": "text", "text": "[The model stopped early: SAFETY.]"}
    ]
    text = from_gemini(candidate([{"text": "hello"}]))
    assert (text.content, text.stop_reason) == ([{"type": "text", "text": "hello"}], "end_turn")
    tool = from_gemini(
        candidate(
            [
                {"functionCall": {"id": "g1", "name": "read_note", "args": {"slug": "x"}}},
                {"functionCall": {"name": "search_notes"}},
            ]
        )
    )
    assert tool.stop_reason == "tool_use"
    assert tool.content[0] == {
        "type": "tool_use",
        "id": "g1",
        "name": "read_note",
        "input": {"slug": "x"},
    }
    assert tool.content[1]["id"].startswith("toolu_")
    assert tool.content[1]["input"] == {}
    assert from_gemini(candidate([{"thought": True}])).content == []


def test_turn_posts_generate_content(api: Api) -> None:
    api.answers += [candidate([{"text": "ok"}]), candidate([{"text": "ok"}])]
    provider = GeminiProvider("gk", "gemini-x")
    assert provider.turn("be brief", [{"role": "user", "content": "hi"}], [TOOL]).content == [
        {"type": "text", "text": "ok"}
    ]
    call = api.last
    assert (call["method"], call["url"]) == ("POST", endpoint("gemini-x"))
    assert call["url"].endswith("/v1beta/models/gemini-x:generateContent")
    assert call["headers"] == {"x-goog-api-key": "gk"}
    assert call["body"] == {
        "contents": [{"role": "user", "parts": [{"text": "hi"}]}],
        "systemInstruction": {"parts": [{"text": "be brief"}]},
        "tools": [
            {
                "functionDeclarations": [
                    {
                        "name": "read_note",
                        "description": "Read a note",
                        "parametersJsonSchema": TOOL.input_schema,
                    }
                ]
            }
        ],
    }
    provider.turn("", [{"role": "user", "content": "hi"}], [])
    assert set(api.last["body"]) == {"contents"}
