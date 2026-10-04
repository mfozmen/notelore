"""Gemini over the Generative Language REST API (v1beta).

Translation at the boundary: Anthropic-style messages become ``contents`` with
``user`` / ``model`` roles (function responses go under ``user``), tools become
``functionDeclarations`` with a plain JSON Schema, and response parts come back
as blocks. Gemini does not always return a call id, so one is synthesized.
"""

from __future__ import annotations

import uuid
from typing import Any

from notelore.providers import http
from notelore.providers.base import (
    AgentResponse,
    Block,
    Message,
    Tool,
    split_blocks,
    tool_use_names,
)

BASE = "https://generativelanguage.googleapis.com/v1beta/models"
TIMEOUT_SECONDS = 60.0


def endpoint(model: str) -> str:
    return f"{BASE}/{model}:generateContent"


def headers(api_key: str) -> dict[str, str]:
    return {"x-goog-api-key": api_key}


class GeminiProvider:
    def __init__(self, api_key: str, model: str) -> None:
        self._api_key, self._model = api_key, model

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        body: dict[str, Any] = {"contents": to_gemini(messages)}
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        if tools:
            body["tools"] = [
                {
                    "functionDeclarations": [
                        {
                            "name": t.name,
                            "description": t.description,
                            "parametersJsonSchema": t.input_schema,
                        }
                        for t in tools
                    ]
                }
            ]
        answer = http.request(
            "POST", endpoint(self._model), headers(self._api_key), body, TIMEOUT_SECONDS
        )
        return from_gemini(answer)


def to_gemini(messages: list[Message]) -> list[dict[str, Any]]:
    names = tool_use_names(messages)
    contents = []
    for message in messages:
        texts, uses, results = split_blocks(message["content"])
        parts: list[dict[str, Any]] = [{"text": t} for t in texts]
        parts += [
            {"functionCall": {"name": u.get("name", ""), "args": u.get("input") or {}}}
            for u in uses
        ]
        parts += [
            {
                "functionResponse": {
                    "name": names.get(str(r.get("tool_use_id", "")), ""),
                    "response": {"result": r.get("content", "")},
                }
            }
            for r in results
        ]
        # Function responses go under role "user", like plain user text.
        contents.append({"role": "user" if message["role"] == "user" else "model", "parts": parts})
    return contents


def from_gemini(answer: dict[str, Any]) -> AgentResponse:
    blocks: list[Block] = []
    candidates = answer.get("candidates") or []
    if not candidates:
        return AgentResponse(blocks, "end_turn")
    candidate = candidates[0]
    for part in (candidate.get("content") or {}).get("parts") or []:
        if part.get("text"):
            blocks.append({"type": "text", "text": part["text"]})
        elif "functionCall" in part:
            call = part["functionCall"]
            blocks.append(
                {
                    "type": "tool_use",
                    "id": call.get("id") or f"toolu_{uuid.uuid4().hex[:12]}",
                    "name": call["name"],
                    "input": dict(call.get("args") or {}),
                }
            )
    tool_use = any(b["type"] == "tool_use" for b in blocks)
    finish = str(candidate.get("finishReason") or "STOP").upper()
    if not tool_use and finish not in {"STOP", "FINISH_REASON_UNSPECIFIED"}:
        blocks.append({"type": "text", "text": f"[The model stopped early: {finish}.]"})
    return AgentResponse(blocks, "tool_use" if tool_use else "end_turn")
