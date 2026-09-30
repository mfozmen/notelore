"""Gemini via the ``google-genai`` SDK.

Translation at the boundary: Anthropic-style messages become Gemini ``Content``
objects (``user`` / ``model`` / ``tool`` roles), tool calls become
``FunctionDeclaration`` tools, and response parts come back as blocks. Gemini
does not always return a call id, so one is synthesized for correlation.
"""

from __future__ import annotations

import uuid
from typing import Any

from notelore.providers.base import (
    AgentResponse,
    Block,
    Message,
    Tool,
    split_blocks,
    tool_use_names,
)

TIMEOUT_MS = 60_000


class GeminiProvider:
    def __init__(self, api_key: str, model: str) -> None:
        self._api_key, self._model = api_key, model

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        from google import genai
        from google.genai import types

        client = genai.Client(
            api_key=self._api_key, http_options=types.HttpOptions(timeout=TIMEOUT_MS)
        )
        config: dict[str, Any] = {"system_instruction": system}
        if tools:
            config["tools"] = [
                types.Tool(
                    function_declarations=[
                        types.FunctionDeclaration(
                            name=t.name,
                            description=t.description,
                            parameters_json_schema=t.input_schema,
                        )
                        for t in tools
                    ]
                )
            ]
        response = client.models.generate_content(
            model=self._model,
            contents=to_gemini(messages, types),
            config=types.GenerateContentConfig(**config),
        )
        return from_gemini(response)


def to_gemini(messages: list[Message], types: Any) -> list[Any]:
    names = tool_use_names(messages)
    contents = []
    for message in messages:
        texts, uses, results = split_blocks(message["content"])
        parts = [types.Part.from_text(text=t) for t in texts]
        parts += [
            types.Part(
                function_call=types.FunctionCall(name=u.get("name", ""), args=u.get("input") or {})
            )
            for u in uses
        ]
        parts += [
            types.Part(
                function_response=types.FunctionResponse(
                    id=r.get("tool_use_id", ""),
                    name=names.get(str(r.get("tool_use_id", "")), ""),
                    response={"result": r.get("content", "")},
                )
            )
            for r in results
        ]
        role = "user" if message["role"] == "user" else "model"  # function responses: user
        contents.append(types.Content(role=role, parts=parts))
    return contents


def from_gemini(response: Any) -> AgentResponse:
    blocks: list[Block] = []
    candidates = getattr(response, "candidates", None) or []
    if not candidates:
        return AgentResponse(blocks, "end_turn")
    candidate = candidates[0]
    for part in getattr(candidate.content, "parts", None) or []:
        if getattr(part, "text", None):
            blocks.append({"type": "text", "text": part.text})
        elif getattr(part, "function_call", None) is not None:
            call = part.function_call
            blocks.append(
                {
                    "type": "tool_use",
                    "id": getattr(call, "id", None) or f"toolu_{uuid.uuid4().hex[:12]}",
                    "name": call.name,
                    "input": dict(call.args or {}),
                }
            )
    tool_use = any(b["type"] == "tool_use" for b in blocks)
    finish = str(getattr(candidate, "finish_reason", "STOP") or "STOP").upper()
    if not tool_use and finish not in {"STOP", "FINISH_REASON_UNSPECIFIED"}:
        blocks.append({"type": "text", "text": f"[The model stopped early: {finish}.]"})
    return AgentResponse(blocks, "tool_use" if tool_use else "end_turn")
